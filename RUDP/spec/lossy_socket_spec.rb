require_relative "../lib/lossy_socket"

# A hand-written stand-in for UDPSocket, deliberately not an RSpec double:
# LossySocket's delayed sends happen on a background thread, and
# rspec-mocks doubles aren't safe to invoke off the main example thread.
class RecordingSocket
  attr_reader :calls

  def initialize
    @calls = []
    @mutex = Mutex.new
  end

  def send(*args)
    @mutex.synchronize { @calls << args }
  end
end

RSpec.describe LossySocket do
  let(:inner_socket) { RecordingSocket.new }

  it "never sends when loss_rate is 1.0" do
    lossy = LossySocket.new(inner_socket, loss_rate: 1.0, max_delay: 0)
    lossy.send("hello", 0, "127.0.0.1", 3000)

    expect(inner_socket.calls).to be_empty
  end

  it "always sends when loss_rate is 0.0" do
    lossy = LossySocket.new(inner_socket, loss_rate: 0.0, max_delay: 0)
    lossy.send("hello", 0, "127.0.0.1", 3000)

    expect(inner_socket.calls).to eq([["hello", 0, "127.0.0.1", 3000]])
  end

  it "sends synchronously (no delay) when max_delay is 0" do
    lossy = LossySocket.new(inner_socket, loss_rate: 0.0, max_delay: 0)
    lossy.send("hello", 0, "127.0.0.1", 3000)

    # if this were backgrounded, nothing here would have given it a chance
    # to run yet -- seeing the call already recorded proves it was synchronous
    expect(inner_socket.calls.size).to eq(1)
  end

  describe "#flush" do
    it "blocks until a delayed send has actually gone out" do
      lossy = LossySocket.new(inner_socket, loss_rate: 0.0, max_delay: 0.2)

      lossy.send("hello", 0, "127.0.0.1", 3000)
      expect(inner_socket.calls).to be_empty # still sleeping out its delay

      lossy.flush

      expect(inner_socket.calls).to eq([["hello", 0, "127.0.0.1", 3000]])
    end
  end
end
