require "socket"
require_relative "lib/rudp_connection"

socket = UDPSocket.new
message = ARGV[0] || "hello"

# Stop-and-wait is just a sliding window of size 1 -- one packet in flight
# at a time, wait for its ACK (or give up) before moving on. RudpConnection
# handles this and the pipelined case (see windowed_client.rb) with the
# same logic, just a different window_size.
MAX_ATTEMPTS = 5
connection = RudpConnection.new(socket, "127.0.0.1", 3000, window_size: 1, packet_timeout: 0.5)

stats = connection.send_all([message], max_attempts: MAX_ATTEMPTS) do |event, seq, payload, attempt|
  case event
  when :sent
    puts "sent #{payload.inspect} (attempt #{attempt}/#{MAX_ATTEMPTS})"
  when :retransmit
    puts "timed out waiting for ACK -- retrying (attempt #{attempt}/#{MAX_ATTEMPTS})"
  when :acked
    puts "got ACK for seq=#{seq} (#{payload.inspect}) after #{attempt} attempt(s)"
  when :gave_up
    puts "gave up after #{attempt} attempts -- server never confirmed delivery"
  end
end

puts "delivered #{stats[:delivered]}/#{stats[:total]}"
