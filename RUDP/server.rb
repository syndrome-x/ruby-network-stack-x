require "socket"
require_relative "lib/lossy_socket" # require_relative resolves the path relative to THIS file, not the cwd

$stdout.sync = true # flush prints immediately instead of buffering

raw_socket = UDPSocket.new
raw_socket.bind("0.0.0.0", 3000)

# Wrap the real socket so every reply we SEND is subject to simulated
# packet loss and random delay -- modeling a flaky network on the return
# path. Receiving (raw_socket.recvfrom below) is left alone: we only
# simulate loss on the way out, which is enough to make the client see
# both dropped and reordered packets.
socket = LossySocket.new(raw_socket, loss_rate: 0.3, max_delay: 1.0)

puts "listening on udp://0.0.0.0:3000 (simulating 30% loss, up to 1s delay on replies)"

loop do
  packet, sender = raw_socket.recvfrom(1024) # sender is [family, port, hostname, ip]
  ip   = sender[3]
  port = sender[1]

  # Packets from the client now look like "SEQ|3|hello". String#split turns
  # that into ["SEQ", "3", "hello"]; the "3" comes back as a String, so
  # .to_i converts it to the integer 3. We keep the limit of 3 so a "|"
  # inside the message itself doesn't get split further.
  type, seq, message = packet.split("|", 3)
  seq = seq.to_i

  puts "got seq=#{seq} #{message.inspect} from #{ip}:#{port}"

  # Reply with an ACK that echoes the same seq number back, so the client
  # can match it to the packet it sent. This ACK travels through the same
  # LossySocket, so it can be dropped or delayed too -- which is exactly
  # what forces the client's retry logic to kick in.
  socket.send("ACK|#{seq}|echo: #{message}", 0, ip, port)
end
