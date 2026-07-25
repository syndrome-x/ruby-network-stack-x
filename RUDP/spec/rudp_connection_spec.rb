require_relative "../lib/rudp_connection"

RSpec.describe RudpConnection do
  # Real loopback UDP sockets, real timing -- but FakePeer gives full
  # control over which packets get acknowledged, so behavior is
  # deterministic instead of depending on LossySocket's randomness.
  let(:socket) { UDPSocket.new }

  after { socket.close }

  it "delivers every message when the peer acknowledges everything" do
    peer = FakePeer.new
    connection = RudpConnection.new(socket, "127.0.0.1", peer.port, window_size: 4, packet_timeout: 0.3, poll_interval: 0.02)

    stats = connection.send_all(%w[a b c d e])

    expect(stats[:delivered]).to eq(5)
    expect(stats[:total]).to eq(5)
    expect(stats[:retransmissions]).to eq(0)
  ensure
    peer&.stop
  end

  it "retransmits a packet whose ACK was dropped, and still delivers it" do
    drop_once = { 0 => true }
    peer = FakePeer.new do |pkt, respond|
      if drop_once[pkt.seq]
        drop_once[pkt.seq] = false # ignore this one delivery, ack every attempt after
      else
        respond.call(pkt.seq)
      end
    end
    connection = RudpConnection.new(socket, "127.0.0.1", peer.port, window_size: 1, packet_timeout: 0.1, poll_interval: 0.02)

    stats = connection.send_all(["only message"])

    expect(stats[:delivered]).to eq(1)
    expect(stats[:retransmissions]).to be >= 1
  ensure
    peer&.stop
  end

  it "never keeps more than window_size packets in flight" do
    peer = FakePeer.new { |_pkt, _respond| } # never acknowledges anything
    connection = RudpConnection.new(socket, "127.0.0.1", peer.port, window_size: 3, packet_timeout: 0.03, poll_interval: 0.01)

    # No max_attempts, so a packet that never gets acked is retried
    # forever rather than freeing up its window slot -- meaning next_seq
    # can never advance past window_size. Run it in the background for a
    # short, bounded window and check what was sent during that time.
    sender_thread = Thread.new { connection.send_all(%w[a b c d e f g h]) }
    sleep 0.2 # long enough for several retransmit cycles
    sender_thread.kill
    sender_thread.join

    expect(peer.received_seqs.uniq.sort).to eq([0, 1, 2])
  ensure
    peer&.stop
  end

  it "gives up after max_attempts and reports it, without delivering that message" do
    peer = FakePeer.new { |_pkt, _respond| } # never acknowledges anything
    connection = RudpConnection.new(socket, "127.0.0.1", peer.port, window_size: 1, packet_timeout: 0.02, poll_interval: 0.01)

    gave_up = []
    stats = connection.send_all(["stuck"], max_attempts: 3) do |event, seq, _payload, attempt|
      gave_up << [seq, attempt] if event == :gave_up
    end

    expect(stats[:delivered]).to eq(0)
    expect(gave_up).to eq([[0, 3]])
  ensure
    peer&.stop
  end

  it "yields :sent, :acked and :retransmit events with increasing attempt counts" do
    drop_once = { 0 => true }
    peer = FakePeer.new do |pkt, respond|
      if drop_once[pkt.seq]
        drop_once[pkt.seq] = false
      else
        respond.call(pkt.seq)
      end
    end
    connection = RudpConnection.new(socket, "127.0.0.1", peer.port, window_size: 1, packet_timeout: 0.1, poll_interval: 0.02)

    events = []
    connection.send_all(["hi"]) { |event, seq, payload, attempt| events << [event, seq, payload, attempt] }

    expect(events.first).to eq([:sent, 0, "hi", 1])
    expect(events.map(&:first)).to include(:retransmit)
    expect(events.last).to eq([:acked, 0, "ack", 2])
  ensure
    peer&.stop
  end
end
