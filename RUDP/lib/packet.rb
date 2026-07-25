# Packet is the single place that knows the wire format: encoding a
# (type, seq, payload) triple as "SEQ|3|hello" for the socket, and parsing
# it back so the rest of the code works with named fields instead of
# re-splitting raw strings everywhere.
class Packet
  attr_reader :type, :seq, :payload

  def initialize(type:, seq:, payload:)
    @type = type
    @seq = seq
    @payload = payload
  end

  def self.data(seq, message)
    new(type: "SEQ", seq: seq, payload: message)
  end

  def self.ack(seq, info)
    new(type: "ACK", seq: seq, payload: info)
  end

  # split(..., 3) caps the split at 3 fields, so a "|" inside the payload
  # itself is preserved instead of being treated as another delimiter.
  def self.parse(raw)
    type, seq, payload = raw.split("|", 3)
    new(type: type, seq: seq.to_i, payload: payload)
  end

  def data?
    type == "SEQ"
  end

  def ack?
    type == "ACK"
  end

  def to_s
    "#{type}|#{seq}|#{payload}"
  end
end
