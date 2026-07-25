require "socket"
require_relative "lib/rudp_connection"

# Sends a batch of packets using a SLIDING WINDOW instead of stop-and-wait
# (compare with client.rb -- same RudpConnection class underneath, just
# window_size: 1 there vs WINDOW_SIZE here).
#
# The idea: instead of 1 packet in flight at a time, we allow up to
# WINDOW_SIZE unacknowledged packets in flight simultaneously. As ACKs come
# back, the window "slides" forward and new packets take their place. Each
# packet has its OWN timeout, so one lost packet only delays itself, not
# the whole batch (this style is called "Selective Repeat"). This is what
# lets throughput scale instead of being capped at 1 packet per
# round-trip-time.

HOST = "127.0.0.1"
PORT = 3000

MESSAGES = (0...10).map { |i| "packet #{i}" }
WINDOW_SIZE = 4       # max unacknowledged packets allowed in flight at once
PACKET_TIMEOUT = 0.5  # seconds to wait for a given packet's ACK before resending it
POLL_INTERVAL = 0.1   # how often RudpConnection checks the socket vs. checking timeouts

socket = UDPSocket.new
connection = RudpConnection.new(
  socket, HOST, PORT,
  window_size: WINDOW_SIZE, packet_timeout: PACKET_TIMEOUT, poll_interval: POLL_INTERVAL
)

stats = connection.send_all(MESSAGES) do |event, seq, payload, attempt|
  case event
  when :sent
    puts "sent seq=#{seq} #{payload.inspect}"
  when :acked
    puts "got ACK for seq=#{seq} (#{payload.inspect})"
  when :retransmit
    puts "seq=#{seq} timed out -- retransmitting (attempt #{attempt})"
  end
end

puts "\n--- summary ---"
puts "delivered: #{stats[:delivered]}/#{stats[:total]} (all acknowledged)"
puts "retransmissions needed: #{stats[:retransmissions]}"
puts "total time: #{stats[:elapsed].round(2)}s"
