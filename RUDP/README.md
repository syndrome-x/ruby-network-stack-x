# RUDP — Reliable UDP, built from scratch in Ruby

A reliability layer built on top of plain UDP: sequence numbers and acknowledgements,
a sliding window with selective-repeat retransmission, duplicate suppression, and
in-order delivery despite a simulated network that drops and reorders packets. No
external networking libraries — just Ruby's `socket` standard library and the
mechanisms TCP itself is built on, implemented and tested from first principles.

The flagship demo reliably transfers an arbitrary file across a network that drops
~30% of packets and randomly reorders the rest, then proves the result is
byte-for-byte identical via SHA256.

## Why

Plain UDP makes no promises: packets can be dropped, duplicated, delayed, or
delivered out of order, and the OS won't tell you. This project builds the missing
reliability layer one mechanism at a time, and includes a simulated lossy network
(`LossySocket`) so every mechanism can be demonstrated and tested against real,
reproducible packet loss — not just described.

## How it works

```
   sender                                          receiver
   ------                                          --------
   RudpConnection                                  ReorderBuffer
   - sliding window (N packets in flight)           - buffers early arrivals
   - per-packet timeout + retransmit                - delivers strictly in order
   - selective repeat (one loss doesn't               (cascades once a gap fills)
     block the rest of the window)                  - dedupes retransmits

            SEQ|0|hello  ------------------>
            SEQ|1|world  ------------------>   (dropped by the network)
                         <------------------   ACK|0|...
            SEQ|1|world  ------------------>   (retransmitted after timeout)
                         <------------------   ACK|1|...
```

Every packet on the wire is a pipe-delimited string: `TYPE|SEQ|PAYLOAD`, where
`TYPE` is `SEQ` (data) or `ACK` (acknowledgement). Payloads can contain arbitrary
bytes — including `|` characters — since parsing caps the split at 3 fields.

**Core library** (`lib/`):

| File | Responsibility |
|---|---|
| `packet.rb` | Wire format: encode/decode `TYPE\|SEQ\|PAYLOAD` |
| `lossy_socket.rb` | Decorates a `UDPSocket`, randomly dropping/delaying sends to simulate a bad network |
| `rudp_connection.rb` | Sender: sliding window, per-packet timeout, selective-repeat retransmission |
| `reorder_buffer.rb` | Receiver: buffers out-of-order arrivals, delivers strictly in sequence, dedupes retransmits |

Stop-and-wait and pipelined sliding-window delivery are the *same* algorithm in
`RudpConnection` — stop-and-wait is just `window_size: 1`.

The file-transfer demo (`send_file.rb` / `receive_file.rb`) also implements a
TIME_WAIT-style grace period: after finishing, the receiver lingers briefly to
re-acknowledge a retransmit in case its own final ACK was lost — the same problem
TCP solves the same way when closing a connection.

## Demos

Each script is a runnable, self-contained demonstration of one piece of the system.
Run them from inside `RUDP/`, two terminals at a time — never run more than one of
`server.rb` / `receive_file.rb` simultaneously, since both bind port 3000.

**Basic reliability** (terminal A: `ruby server.rb`, terminal B: any of these):

```bash
ruby client.rb "hello there"   # stop-and-wait: one message, retried until acked
ruby windowed_client.rb        # sliding window: 10 messages, pipelined delivery
ruby burst_client.rb           # no reliability at all -- watch raw loss/reordering
ruby reorder_demo.rb           # deterministic proof of the reorder buffer's cascade delivery
```

**File transfer** (terminal A: `ruby receive_file.rb`, terminal B: `ruby send_file.rb [path]`):

```bash
ruby receive_file.rb                       # terminal A
ruby send_file.rb                          # terminal B -- sends sample_files/hello.txt
ruby send_file.rb /path/to/any/file        # or any file, text or binary

diff sample_files/hello.txt received/hello.txt   # independent verification
```

## Tests

```bash
bundle install   # or: gem install rspec
bundle exec rspec
```

24 examples covering the wire format (including binary-safety and embedded `|`
bytes), the reorder buffer's ordering/cascade/dedup logic, `LossySocket`'s drop/delay
behavior, and `RudpConnection`'s window limits, retransmission, and give-up handling
— the latter driven over real loopback UDP sockets against a scriptable fake peer
(`spec/support/fake_peer.rb`) for deterministic, non-flaky network tests.

## Project structure

```
RUDP/
├── lib/
│   ├── packet.rb              # wire format: encode/decode TYPE|SEQ|PAYLOAD
│   ├── lossy_socket.rb        # UDPSocket decorator simulating loss + delay
│   ├── reorder_buffer.rb      # receiver: in-order delivery, dedup
│   └── rudp_connection.rb     # sender: sliding window, retransmission
├── spec/
│   ├── spec_helper.rb
│   ├── support/fake_peer.rb    # scriptable UDP peer used by rudp_connection_spec.rb
│   └── *_spec.rb                # one spec file per lib/ class
├── sample_files/hello.txt      # file-transfer demo asset
├── client.rb                   # stop-and-wait demo
├── windowed_client.rb          # sliding-window demo
├── burst_client.rb             # unreliable baseline (no retry logic)
├── reorder_demo.rb             # deterministic reorder-buffer proof
├── server.rb                   # generic echo server
├── send_file.rb                # file transfer -- sender
├── receive_file.rb             # file transfer -- receiver
└── Gemfile / .rspec            # test tooling
```
