require "socket"
require "digest"
require_relative "lib/lossy_socket"
require_relative "lib/packet"
require_relative "lib/reorder_buffer"

# The receiving half of the send_file.rb demo: listens for one incoming
# file transfer, reassembles it in order using ReorderBuffer, and verifies
# the result against the sender's SHA256 checksum before writing it out.
# Unlike server.rb (a generic echo server that loops forever), this exits
# once a single transfer completes -- it's a one-shot demo, not a service.

HOST = "0.0.0.0"
PORT = 3000
OUTPUT_DIR = File.join(__dir__, "received")

# After we've reassembled the file, our OWN final ACK can still be lost on
# the way back (it travels through the same lossy socket as every other
# ACK). If that happens, the sender never finds out its last packet
# arrived and retransmits it -- but if we've already exited, nothing is
# there to re-ACK it, and the sender retries forever. So instead of exiting
# the instant we're done, we keep answering for a bit longer, just in case.
# TCP has the exact same problem and the exact same fix: this is a
# (much simplified) version of TCP's TIME_WAIT state.
GRACE_PERIOD = 2.0 # seconds to keep re-ACKing after completion

$stdout.sync = true

raw_socket = UDPSocket.new
raw_socket.bind(HOST, PORT)

# ACKs we send back go through the same simulated lossy network as every
# other script in this project -- incoming file chunks are NOT lossy
# (LossySocket only wraps outgoing sends), which is why the sender's
# retransmission logic is what's actually responsible for getting
# everything through, not luck.
socket = LossySocket.new(raw_socket, loss_rate: 0.3, max_delay: 1.0)

reorder_buffer = ReorderBuffer.new

puts "listening on udp://#{HOST}:#{PORT} for an incoming file transfer..."

filename = nil
expected_checksum = nil
total_expected = nil # 1 (metadata) + chunk_count, known once metadata (seq 0) arrives
chunks = []           # chunks[i] holds chunk i's bytes once delivered
delivered_count = 0
completed = false
grace_deadline = nil

loop do
  # Before completion, wait indefinitely (timeout: nil) for the next
  # packet, same as a plain blocking recvfrom. After completion, only wait
  # until grace_deadline -- if nothing arrives (no retransmit needed)
  # before then, we're done for real and can exit.
  if completed
    remaining = grace_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    break if remaining <= 0
    ready = IO.select([raw_socket], nil, nil, remaining)
    break unless ready
  end

  raw, sender = raw_socket.recvfrom(1500)
  ip, port = sender[3], sender[1]
  from = "#{ip}:#{port}"

  pkt = Packet.parse(raw)
  result = reorder_buffer.receive(from, pkt.seq, pkt.payload)

  # ACK every packet regardless of what ReorderBuffer made of it -- the
  # sender only needs to know ITS packet arrived; whether it was new,
  # buffered, or a duplicate is purely our own bookkeeping.
  ack = Packet.ack(pkt.seq, "received")
  socket.send(ack.to_s, 0, ip, port)

  next unless result.is_a?(Array) # :old / :duplicate -- nothing newly ready to process

  result.each do |deliver_seq, payload|
    if deliver_seq.zero?
      filename, chunk_count_str, byte_size_str, expected_checksum = payload.split("|", 4)
      total_expected = chunk_count_str.to_i + 1
      puts "receiving #{filename.inspect}: #{chunk_count_str} chunks, #{byte_size_str} bytes expected"
    else
      chunks[deliver_seq - 1] = payload
    end

    delivered_count += 1
    print "\rreceiving... #{delivered_count}/#{total_expected || "?"} packets delivered in order"
  end

  next unless total_expected && delivered_count == total_expected

  puts
  data = chunks.join
  actual_checksum = Digest::SHA256.hexdigest(data)

  Dir.mkdir(OUTPUT_DIR) unless Dir.exist?(OUTPUT_DIR)
  output_path = File.join(OUTPUT_DIR, filename)
  File.binwrite(output_path, data)

  puts "wrote #{data.bytesize} bytes to #{output_path}"
  if actual_checksum == expected_checksum
    puts "checksum OK (sha256 #{actual_checksum}) -- byte-for-byte identical to what was sent"
  else
    puts "CHECKSUM MISMATCH -- expected #{expected_checksum}, got #{actual_checksum}"
  end

  completed = true
  grace_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GRACE_PERIOD
  puts "(sticking around for #{GRACE_PERIOD}s in case our last ACK got lost and the sender retries)"
end

# Make sure every ACK we handed to the lossy socket actually finishes
# sending before the process exits -- otherwise one still mid-delay on a
# background thread would be silently killed, never sent at all (see
# lib/lossy_socket.rb#flush).
socket.flush
