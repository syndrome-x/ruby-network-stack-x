require_relative "../lib/packet"

RSpec.describe Packet do
  describe ".data" do
    it "builds a SEQ-type packet carrying the given seq and message" do
      packet = Packet.data(3, "hello")

      expect(packet.type).to eq("SEQ")
      expect(packet.seq).to eq(3)
      expect(packet.payload).to eq("hello")
      expect(packet.data?).to eq(true)
      expect(packet.ack?).to eq(false)
    end
  end

  describe ".ack" do
    it "builds an ACK-type packet carrying the given seq and info" do
      packet = Packet.ack(3, "echo: hello")

      expect(packet.type).to eq("ACK")
      expect(packet.seq).to eq(3)
      expect(packet.payload).to eq("echo: hello")
      expect(packet.ack?).to eq(true)
      expect(packet.data?).to eq(false)
    end
  end

  describe "#to_s" do
    it "encodes as TYPE|SEQ|PAYLOAD" do
      expect(Packet.data(3, "hello").to_s).to eq("SEQ|3|hello")
      expect(Packet.ack(3, "echo: hello").to_s).to eq("ACK|3|echo: hello")
    end
  end

  describe ".parse" do
    it "round-trips a packet built by .data" do
      raw = Packet.data(7, "packet 7").to_s
      parsed = Packet.parse(raw)

      expect(parsed.type).to eq("SEQ")
      expect(parsed.seq).to eq(7)
      expect(parsed.payload).to eq("packet 7")
    end

    it "round-trips a packet built by .ack" do
      raw = Packet.ack(7, "echo: packet 7").to_s
      parsed = Packet.parse(raw)

      expect(parsed.type).to eq("ACK")
      expect(parsed.seq).to eq(7)
      expect(parsed.payload).to eq("echo: packet 7")
    end

    it "preserves '|' characters inside the payload instead of splitting on them" do
      payload = "a|b|c"
      parsed = Packet.parse(Packet.data(0, payload).to_s)

      expect(parsed.payload).to eq(payload)
    end

    it "preserves arbitrary binary bytes in the payload, including embedded '|' bytes" do
      binary = "\xFF\x00|\xFE\x7C".b
      parsed = Packet.parse(Packet.data(0, binary).to_s)

      expect(parsed.payload.b).to eq(binary)
    end

    it "converts the seq field to an Integer" do
      parsed = Packet.parse("SEQ|42|hi")
      expect(parsed.seq).to eq(42)
      expect(parsed.seq).to be_a(Integer)
    end
  end
end
