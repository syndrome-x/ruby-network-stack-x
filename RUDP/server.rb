require "socket"
require_relative "lib/lossy_socket"
require_relative "lib/packet"
require_relative "lib/reorder_buffer"

$stdout.sync = true # flush prints immediately instead of buffering

raw_socket = UDPSocket.new
raw_socket.bind("0.0.0.0", 3000)

# Wrap the real socket so every reply we SEND is subject to simulated
# packet loss and random delay -- modeling a flaky network on the return
# path. Receiving (raw_socket.recvfrom below) is left alone: we only
# simulate loss on the way out, which is enough to make the client see
# both dropped and reordered packets.
socket = LossySocket.new(raw_socket, loss_rate: 0.3, max_delay: 1.0)

# Packets can arrive both duplicated (client retransmits) AND out of order
# (the network reorders them). ReorderBuffer handles both: it hands back
# only genuinely-new packets, and only in ascending seq order, buffering
# anything that arrives ahead of schedule until the gap in front of it
# fills. See lib/reorder_buffer.rb for how it works.
reorder_buffer = ReorderBuffer.new

puts "listening on udp://0.0.0.0:3000 (simulating 30% loss, up to 1s delay on replies)"

loop do
  raw, sender = raw_socket.recvfrom(1024) # sender is [family, port, hostname, ip]
  ip   = sender[3]
  port = sender[1]
  from = "#{ip}:#{port}"

  pkt = Packet.parse(raw)
  seq = pkt.seq
  message = pkt.payload

  result = reorder_buffer.receive(from, seq, message)

  case result
  when :old
    puts "got seq=#{seq} #{message.inspect} from #{from} (old duplicate, already delivered -- skipping)"
  when :duplicate
    puts "got seq=#{seq} #{message.inspect} from #{from} (duplicate, already buffered -- skipping)"
  else
    puts "got seq=#{seq} #{message.inspect} from #{from}"
    if result.empty?
      puts "  .. out of order -- buffering until earlier packets arrive"
    else
      # ...this is where real "work" (writing to a DB, applying a
      # payment, etc) would happen -- exactly once per seq, and always in
      # order, no matter how many times a packet is retransmitted or how
      # badly the network reorders things.
      result.each do |deliver_seq, deliver_msg|
        puts "  -> delivering seq=#{deliver_seq} #{deliver_msg.inspect} to application (in order)"
      end
    end
  end

  # Reply with an ACK every time, duplicate or not -- the client only cares
  # that ITS packet made it; it doesn't know or care whether we'd already
  # seen it. This ACK travels through the same LossySocket, so it can be
  # dropped or delayed too -- which is exactly what forces the client's
  # retry logic to kick in in the first place.
  ack = Packet.ack(seq, "echo: #{message}")
  socket.send(ack.to_s, 0, ip, port)
end
