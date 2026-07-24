require "socket"

# LossySocket decorates a real UDPSocket so that outgoing packets can be
# randomly dropped or delayed -- simulating an unreliable network, without
# needing an actual bad network to test against.
#
# This is a common Ruby pattern called "delegation" (a form of the
# Decorator pattern): instead of subclassing UDPSocket, we hold a
# reference to a real one (@socket) and forward calls to it, adding our
# own behavior around the call. `class Foo ... end` is how you define a
# class in Ruby; `initialize` is the constructor, called by `.new`.
class LossySocket
  def initialize(udp_socket, loss_rate:, max_delay:)
    @socket    = udp_socket # the real UDPSocket we forward to (@ = instance variable)
    @loss_rate = loss_rate  # chance (0.0-1.0) a packet is dropped entirely
    @max_delay = max_delay  # max seconds a packet may be delayed before sending
  end

  # Same call signature as UDPSocket#send, but may silently drop the
  # packet, or delay it on a background thread before it actually goes out.
  def send(message, flags, ip, port)
    if rand < @loss_rate # rand returns a random Float between 0.0 and 1.0
      puts "  [network] dropped #{message.inspect}"
      return # bail out early -- the packet is simply never sent
    end

    delay = rand * @max_delay
    if delay.zero?
      @socket.send(message, flags, ip, port)
    else
      # Thread.new starts a new thread running this block CONCURRENTLY and
      # returns immediately, so `send` doesn't block here waiting for the
      # sleep. That's what lets a LATER call to `send` (with little or no
      # delay) overtake this one and actually reach the network first --
      # i.e. this is how we simulate out-of-order delivery.
      Thread.new do
        sleep delay
        @socket.send(message, flags, ip, port)
      end
    end
  end
end
