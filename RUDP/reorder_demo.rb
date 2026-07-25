require "socket"
require_relative "lib/packet"

# A focused, DETERMINISTIC demonstration of the server's reorder buffer
# (lib/reorder_buffer.rb) -- rather than relying on the simulated network
# to randomly scramble packets (see windowed_client.rb, which sometimes
# does and sometimes doesn't), this script sends 5 packets in a
# deliberately scrambled order itself, so the effect is guaranteed and
# repeatable.
#
# Note: LossySocket is only applied to the SERVER's outgoing replies, not
# to packets arriving at the server (see server.rb) -- so every packet
# sent here is guaranteed to reach the server, in exactly this send order.
# Watch the server's log while this runs.

HOST = "127.0.0.1"
PORT = 3000

MESSAGES = { 0 => "alpha", 1 => "bravo", 2 => "charlie", 3 => "delta", 4 => "echo" }
SEND_ORDER = [0, 2, 4, 1, 3] # deliberately out of sequence

socket = UDPSocket.new

puts "sending 5 packets in scrambled order: #{SEND_ORDER.inspect}"
puts "(their true sequence order is 0, 1, 2, 3, 4)\n\n"

SEND_ORDER.each do |seq|
  packet = Packet.data(seq, MESSAGES[seq])
  socket.send(packet.to_s, 0, HOST, PORT)
  puts "sent seq=#{seq} #{MESSAGES[seq].inspect}"
  sleep 0.2 # spread the sends out so the server's log is easy to read line-by-line
end

puts "\ndone -- check the server's log: despite arriving in the scrambled order above,"
puts "it should report delivering seq 0, 1, 2, 3, 4 to \"the application\" in that exact"
puts "order, buffering 2 and 4 until their missing predecessors (1 and 3) show up."
