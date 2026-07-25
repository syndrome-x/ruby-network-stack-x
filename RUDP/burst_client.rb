require "socket"
require_relative "lib/packet"

# Sends a burst of numbered packets to the server as fast as possible, then
# listens for a few seconds to see which ACKs come back, and in what order.
#
# Unlike client.rb (which waits for each ACK and retries on loss),
# this script fires everything at once without waiting for anything.
# It's here to make the raw damage the network does VISIBLE -- some ACKs
# won't come back at all (dropped), and the ones that do may arrive out of
# order (delayed). client.rb's retry loop is how RUDP recovers from this;
# this script is the "before" picture. It speaks the same SEQ/ACK protocol
# as client.rb and server.rb now use, just without the retry logic.

HOST = "127.0.0.1"
PORT = 3000
PACKET_COUNT = 10
LISTEN_SECONDS = 3

socket = UDPSocket.new

# 1. Fire off all packets immediately, each tagged with its own sequence
#    number -- we don't wait for an ACK between sends, since the whole
#    point here is to see what un-retried UDP delivery looks like.
PACKET_COUNT.times do |seq|
  packet = Packet.data(seq, "packet #{seq}")
  socket.send(packet.to_s, 0, HOST, PORT)
  puts "sent #{packet}"
end

# 2. Collect whatever ACKs arrive within the listen window.
received_seqs = []
# CLOCK_MONOTONIC only ever moves forward (unlike Time.now, which can jump
# backward on a system clock adjustment) -- important here since a
# backward jump would make `remaining` come out too large and this loop
# would wait far longer than LISTEN_SECONDS actually intends.
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LISTEN_SECONDS

loop do
  remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  break if remaining <= 0

  # IO.select blocks until `socket` has data to read, OR `remaining`
  # seconds pass -- whichever comes first. This lets us wait for ACKs
  # WITHOUT blocking forever if some of them never show up.
  ready = IO.select([socket], nil, nil, remaining)
  break unless ready # nil means we timed out with nothing left to read

  reply, _sender = socket.recvfrom(1024)

  reply_pkt = Packet.parse(reply)
  received_seqs << reply_pkt.seq
  puts "recv seq=#{reply_pkt.seq} (#{reply_pkt.payload.inspect})"
end

# 3. Compare what we sent vs. what came back.
puts "\n--- summary ---"
puts "sent:     #{PACKET_COUNT}"
puts "received: #{received_seqs.size}"

all_seqs = (0...PACKET_COUNT).to_a
missing = all_seqs - received_seqs
puts "lost:     #{missing.size} #{missing.inspect}"

puts "arrival order:  #{received_seqs.inspect}"
puts "arrived in the order sent? #{received_seqs == received_seqs.sort}"
