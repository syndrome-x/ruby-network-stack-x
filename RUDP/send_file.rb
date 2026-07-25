require "socket"
require "digest"
require_relative "lib/rudp_connection"

# The payoff demo: reliably transfer an arbitrary file across the
# simulated lossy network (see lib/lossy_socket.rb) and prove, via a
# SHA256 checksum, that what arrives is byte-for-byte identical to what
# was sent -- despite ~30% packet loss and random reordering along the way.
# Pair with receive_file.rb, which does the reassembly + verification.

HOST = "127.0.0.1"
PORT = 3000
CHUNK_SIZE = 1000 # keep each packet comfortably under a typical 1500-byte network MTU, header included
WINDOW_SIZE = 4

# receive_file.rb only stays alive for a short grace period after it
# finishes (to re-ACK a retransmit if its own final ACK was lost -- see
# the comment there). A generous but finite MAX_ATTEMPTS means this script
# can never hang forever even in the unlucky case where several attempts
# in a row are all dropped; it fails loudly instead.
MAX_ATTEMPTS = 30

path = ARGV[0] || File.join(__dir__, "sample_files", "hello.txt")
abort "no such file: #{path}" unless File.exist?(path)

# binread reads raw bytes with no text-encoding conversion -- RUDP moves
# bytes, not text, so it shouldn't (and doesn't) care whether the file is
# a text document or something completely binary.
data = File.binread(path)
filename = File.basename(path)
checksum = Digest::SHA256.hexdigest(data)

# Split into fixed-size byte chunks. String#byteslice operates on raw
# bytes rather than characters, so this works correctly regardless of the
# file's encoding or content.
chunks = []
offset = 0
while offset < data.bytesize
  chunks << data.byteslice(offset, CHUNK_SIZE)
  offset += CHUNK_SIZE
end
chunks << "" if chunks.empty? # guard against a zero-byte input file

# The receiver needs to know what's coming before it can reassemble
# anything -- filename, how many chunks to expect, and a checksum to
# verify against once it's done. We send that as message 0 (seq 0), ahead
# of the real chunks; RudpConnection treats it like any other message, so
# it gets the exact same reliability guarantees as the file data itself.
meta = "#{filename}|#{chunks.size}|#{data.bytesize}|#{checksum}"
messages = [meta] + chunks

puts "sending #{filename.inspect}: #{data.bytesize} bytes across #{chunks.size} chunks (sha256 #{checksum})"

socket = UDPSocket.new
connection = RudpConnection.new(socket, HOST, PORT, window_size: WINDOW_SIZE, packet_timeout: 0.5)

acked_count = 0
gave_up_seqs = []
stats = connection.send_all(messages, max_attempts: MAX_ATTEMPTS) do |event, seq, _payload, _attempt|
  case event
  when :acked
    acked_count += 1
    percent = (acked_count * 100.0 / messages.size).round(1)
    print "\rsending... #{acked_count}/#{messages.size} packets acknowledged (#{percent}%)"
    $stdout.flush
  when :gave_up
    gave_up_seqs << seq
  end
end
puts

if gave_up_seqs.empty?
  puts "done in #{stats[:elapsed].round(2)}s -- #{stats[:retransmissions]} retransmissions were needed due to simulated loss"
else
  puts "done in #{stats[:elapsed].round(2)}s -- WARNING: gave up on #{gave_up_seqs.size} packet(s) after #{MAX_ATTEMPTS} attempts each: #{gave_up_seqs.inspect}"
  puts "(the receiver's reconstruction will be incomplete/incorrect -- this should be rare; try again)"
end
