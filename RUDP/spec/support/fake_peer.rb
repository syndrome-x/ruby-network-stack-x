require "socket"
require_relative "../../lib/packet"

# A minimal stand-in for a UDP peer, used to drive RudpConnection specs
# deterministically: real loopback sockets (so timing/window behavior is
# exercised for real), but with the test controlling exactly which packets
# get acknowledged, instead of relying on LossySocket's randomness.
class FakePeer
  attr_reader :port, :received_seqs

  # on_packet: ->(packet, respond) { ... }. Call respond.call(seq) to send
  # an ACK back for that seq; omit it to simulate a dropped/ignored packet.
  # Defaults to acknowledging everything immediately.
  def initialize(&on_packet)
    @socket = UDPSocket.new
    @socket.bind("127.0.0.1", 0)
    @port = @socket.addr[1]
    @on_packet = on_packet || ->(pkt, respond) { respond.call(pkt.seq) }
    @received_seqs = []
    @mutex = Mutex.new
    @thread = Thread.new { run }
  end

  def stop
    @thread.kill
    @socket.close
  end

  private

  def run
    loop do
      raw, sender = @socket.recvfrom(1024)
      pkt = Packet.parse(raw)
      @mutex.synchronize { @received_seqs << pkt.seq }

      respond = lambda do |seq, info = "ack"|
        @socket.send(Packet.ack(seq, info).to_s, 0, sender[3], sender[1])
      end

      @on_packet.call(pkt, respond)
    end
  rescue IOError, Errno::EBADF
    # socket was closed via #stop -- thread exiting is expected
  end
end
