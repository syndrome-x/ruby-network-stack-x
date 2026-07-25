require_relative "packet"

# RudpConnection is the reusable engine behind both client.rb and
# windowed_client.rb: reliably delivering a batch of messages to one UDP
# peer using a sliding window with per-packet timeout and retransmission
# (Selective Repeat -- see windowed_client.rb's comments for why sliding
# windows beat stop-and-wait on throughput).
#
# Stop-and-wait isn't a separate code path here -- it's just what you get
# when window_size: 1. One class, one algorithm, two configurations.
class RudpConnection
  def initialize(socket, host, port, window_size: 4, packet_timeout: 0.5, poll_interval: 0.1)
    @socket = socket
    @host = host
    @port = port
    @window_size = window_size
    @packet_timeout = packet_timeout
    @poll_interval = poll_interval
  end

  # Reliably sends every element of `messages` (assigning them seq numbers
  # 0, 1, 2, ... in order), blocking until each is acknowledged -- or, if
  # `max_attempts` is given, until it's been retried that many times and
  # given up on. Without max_attempts, a stuck packet is retried forever.
  #
  # If a block is given, it's called as `yield(event, seq, payload,
  # attempt)` for :sent, :acked, :retransmit, :gave_up. This method never
  # logs anything itself -- that's entirely up to the caller.
  #
  # Returns a summary Hash: :delivered, :total, :retransmissions, :elapsed.
  def send_all(messages, max_attempts: nil)
    next_seq = 0
    in_flight = {}            # seq => monotonic time it was (most recently) sent
    attempts = Hash.new(0)    # seq => how many times we've sent it so far
    acked = Array.new(messages.size, false)
    retransmit_count = 0
    started_at = monotonic_now

    # Keep going until there's nothing left to send AND nothing still
    # outstanding -- NOT "until everything is acked", since a packet that
    # hits max_attempts is removed from in_flight without ever being acked.
    until in_flight.empty? && next_seq >= messages.size
      # 1. Fill the window with brand-new packets while there's room.
      while in_flight.size < @window_size && next_seq < messages.size
        transmit(next_seq, messages[next_seq])
        attempts[next_seq] += 1
        in_flight[next_seq] = monotonic_now
        yield(:sent, next_seq, messages[next_seq], attempts[next_seq]) if block_given?
        next_seq += 1
      end

      # 2. Wait briefly for any reply.
      ready = IO.select([@socket], nil, nil, @poll_interval)

      if ready
        reply, _sender = @socket.recvfrom(1024)
        reply_pkt = Packet.parse(reply)
        seq = reply_pkt.seq

        if reply_pkt.ack? && in_flight.key?(seq)
          acked[seq] = true
          in_flight.delete(seq)
          yield(:acked, seq, reply_pkt.payload, attempts[seq]) if block_given?
        end
      end

      # 3. Handle any packet whose own timer expired. We collect the
      #    expired seqs into a plain Array first (via select+keys) rather
      #    than mutating in_flight while iterating it directly -- safer,
      #    since we delete some of those keys below.
      now = monotonic_now
      expired_seqs = in_flight.select { |_seq, sent_at| now - sent_at > @packet_timeout }.keys

      expired_seqs.each do |seq|
        if max_attempts && attempts[seq] >= max_attempts
          in_flight.delete(seq)
          yield(:gave_up, seq, messages[seq], attempts[seq]) if block_given?
        else
          transmit(seq, messages[seq])
          attempts[seq] += 1
          in_flight[seq] = now
          retransmit_count += 1
          yield(:retransmit, seq, messages[seq], attempts[seq]) if block_given?
        end
      end
    end

    {
      delivered: acked.count(true),
      total: messages.size,
      retransmissions: retransmit_count,
      elapsed: monotonic_now - started_at,
    }
  end

  private

  def transmit(seq, message)
    packet = Packet.data(seq, message)
    @socket.send(packet.to_s, 0, @host, @port)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
