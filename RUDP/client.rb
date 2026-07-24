require "socket"

socket = UDPSocket.new

message = ARGV[0] || "hello"

# The "reliable" part of RUDP starts here: every packet gets a sequence
# number. The server echoes it back in its ACK so we know exactly which
# packet was acknowledged (useful once we're juggling more than one).
# We only send a single packet in this script, so it's always 0.
seq = 0
packet = "SEQ|#{seq}|#{message}"

MAX_RETRIES = 5
TIMEOUT = 0.5 # seconds -- shorter than a single wait, since we may need several attempts

attempt = 0
acked = false

# `until acked || attempt >= MAX_RETRIES` reads as "keep looping until we're
# acked, or we've run out of attempts". Ruby's `until` is just `while` with
# the condition flipped -- `until x` means `while !x`.
until acked || attempt >= MAX_RETRIES
  attempt += 1
  socket.send(packet, 0, "127.0.0.1", 3000)
  puts "sent #{packet.inspect} (attempt #{attempt}/#{MAX_RETRIES})"

  ready = IO.select([socket], nil, nil, TIMEOUT)

  if ready
    reply, sender = socket.recvfrom(1024)

    # reply looks like "ACK|0|echo: hello". split("|", 3) caps it at 3
    # pieces so a "|" inside the echoed message doesn't get chopped up too.
    # This is a "multiple assignment" -- Ruby unpacks the returned array
    # into type, acked_seq, and info in one line.
    type, acked_seq, info = reply.split("|", 3)

    if type == "ACK" && acked_seq.to_i == seq
      puts "got ACK for seq=#{seq} (#{info.inspect}) from #{sender[3]}:#{sender[1]}"
      acked = true
    else
      # Could be a stray/duplicate packet from elsewhere -- ignore it and
      # keep waiting out the current timeout window implicitly (we just
      # loop back around, which sends again; good enough for stop-and-wait).
      puts "got unexpected reply #{reply.inspect}, ignoring"
    end
  else
    puts "timed out after #{TIMEOUT}s waiting for ACK -- retrying"
  end
end

unless acked
  puts "gave up after #{MAX_RETRIES} attempts -- server never confirmed delivery"
end
