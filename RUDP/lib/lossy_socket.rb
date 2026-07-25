require "socket"

# LossySocket decorates a real UDPSocket so that outgoing packets can be
# randomly dropped or delayed -- simulating an unreliable network, without
# needing an actual bad network to test against.
class LossySocket
  def initialize(udp_socket, loss_rate:, max_delay:)
    @socket    = udp_socket
    @loss_rate = loss_rate  # chance (0.0-1.0) a packet is dropped entirely
    @max_delay = max_delay  # max seconds a packet may be delayed before sending
    @pending   = []         # background threads currently sleeping before a delayed send
  end

  # Same call signature as UDPSocket#send, but may silently drop the
  # packet, or delay it on a background thread before it actually goes out.
  def send(message, flags, ip, port)
    if rand < @loss_rate
      puts "  [network] dropped #{message.inspect}"
      return
    end

    delay = rand * @max_delay
    if delay.zero?
      @socket.send(message, flags, ip, port)
    else
      # Sending on a background thread lets this call return immediately,
      # so a later call with little or no delay can overtake it and reach
      # the network first -- this is how out-of-order delivery is simulated.
      @pending << Thread.new do
        sleep delay
        @socket.send(message, flags, ip, port)
      end
      @pending.select!(&:alive?) # opportunistic cleanup so this array doesn't grow forever on a long-running server
    end
  end

  # Ruby kills every background thread the instant the main thread exits --
  # without this, a packet that was "sent" (not dropped, just still
  # sleeping out its simulated delay) could vanish silently on shutdown:
  # never dropped, never delivered, just never actually sent. Scripts that
  # exit intentionally after using a LossySocket (see receive_file.rb)
  # should call this first, so any last delayed packet actually goes out.
  def flush
    @pending.each(&:join)
    @pending.clear
  end
end
