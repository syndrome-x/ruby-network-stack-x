# ReorderBuffer makes sure packets are handed to "the application" in
# sequence order, even when the network delivered them out of order.
# Each sender gets independent ordering state, since two different clients
# have entirely separate sequence spaces.
class ReorderBuffer
  def initialize
    @next_expected = Hash.new(0)                       # sender => next in-order seq we're waiting to deliver
    @pending = Hash.new { |hash, key| hash[key] = {} }  # sender => { seq => payload } for early arrivals
  end

  # Records that `payload` arrived for `seq` from `sender`. Returns:
  #   :old       -- this seq was already delivered before; ignore it
  #   :duplicate -- it's a duplicate of a packet we're already holding,
  #                 buffered, but not yet delivered; ignore it
  #   Array      -- packet accepted. Empty if it arrived early and is now
  #                 waiting for earlier gaps to fill; otherwise one or more
  #                 [seq, payload] pairs now ready to deliver IN ORDER
  #                 (this packet may have filled a gap that unblocks
  #                 several previously-buffered packets at once)
  def receive(sender, seq, payload)
    return :old if seq < @next_expected[sender]
    return :duplicate if @pending[sender].key?(seq)

    @pending[sender][seq] = payload

    ready = []
    while @pending[sender].key?(@next_expected[sender])
      deliver_seq = @next_expected[sender]
      ready << [deliver_seq, @pending[sender].delete(deliver_seq)]
      @next_expected[sender] += 1
    end
    ready
  end
end
