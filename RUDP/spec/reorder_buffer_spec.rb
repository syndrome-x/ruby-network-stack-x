require_relative "../lib/reorder_buffer"

RSpec.describe ReorderBuffer do
  subject(:buffer) { ReorderBuffer.new }

  it "delivers an in-order packet immediately" do
    result = buffer.receive("peer", 0, "alpha")
    expect(result).to eq([[0, "alpha"]])
  end

  it "delivers consecutive in-order packets one at a time, each as soon as it arrives" do
    expect(buffer.receive("peer", 0, "alpha")).to eq([[0, "alpha"]])
    expect(buffer.receive("peer", 1, "bravo")).to eq([[1, "bravo"]])
    expect(buffer.receive("peer", 2, "charlie")).to eq([[2, "charlie"]])
  end

  it "buffers a packet that arrives ahead of schedule, delivering nothing yet" do
    buffer.receive("peer", 0, "alpha")
    result = buffer.receive("peer", 2, "charlie") # seq 1 hasn't arrived yet

    expect(result).to eq([])
  end

  it "cascades delivery of buffered packets once the gap in front of them fills" do
    buffer.receive("peer", 0, "alpha")
    buffer.receive("peer", 2, "charlie") # buffered, waiting on seq 1
    buffer.receive("peer", 3, "delta")   # buffered, waiting on seq 1

    result = buffer.receive("peer", 1, "bravo") # fills the gap

    expect(result).to eq([[1, "bravo"], [2, "charlie"], [3, "delta"]])
  end

  it "returns :old for a duplicate of an already-delivered packet" do
    buffer.receive("peer", 0, "alpha")
    expect(buffer.receive("peer", 0, "alpha")).to eq(:old)
  end

  it "returns :duplicate for a duplicate of a packet that's buffered but not yet delivered" do
    buffer.receive("peer", 0, "alpha")
    buffer.receive("peer", 2, "charlie") # buffered

    expect(buffer.receive("peer", 2, "charlie")).to eq(:duplicate)
  end

  it "keeps independent ordering state per sender" do
    buffer.receive("peer-a", 0, "a0")
    result_b = buffer.receive("peer-b", 0, "b0") # peer-b's first packet, unrelated to peer-a's state

    expect(result_b).to eq([[0, "b0"]])
  end
end
