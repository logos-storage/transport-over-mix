Transport layer over Mix - draft spec
-------------------------------------

### Motivation

Mix supports the following basic communication pattern:

- sending a fixed size packet (currently about 4kb) to someone with a public IP address, but (hopefully) hiding the sender's identity;
- optionally getting back a reply of the same size (via a SURB, "Single Use Reply Block"), while still staying anonymous (at least most of the time).
- there is no guarantee of delivery or ordering
- however, as long as both endpoints is "part of the Mix" (so no Tor-like exit relays), we can assume that packets an encrypted, and their integrity is protected

This is simply not enough for most application, in particular definitely not enough for Logos Storage, where an anonymous user wants to download (and possibly also upload) large files.

Hence this proposal for an abstraction layer which sits between "raw" Mix and the application, allowing for a more conventional communication interface. 

### Socket abstraction

The application would use the transport layer abstraction, which should mostly hide the fact that there is an underlying mixnet.

As most network communication already uses a socket API, it seems to be a natural fit to offer a similar abstraction here too.

A socket is a bidirectional channel of streams, into which both parties can send information (bytes), and which is assumed to be ordered and more-or-less reliable.

This abstraction is very simple:

- one party (typically the client) opens a _session_ with another party (typically the server)
- both parties can send data to the other party, without waiting for any synchronization to happen
- finally the session can be closed (either manually or by some automation, eg. a timeout)

Probably the biggest difference between our proposal and usual Unix sockets is that the streams are not _streams of bytes_, but streams of _larger messages_ (still consisting bytes) instead. This fits the mechanics of the underlying Mix network much better.

### Transport layer API

In pseudocode (using Haskell syntax), the API could look something like this:

```haskell
data Result a
  = Success a
  | Failure String

type IOResult a = IO (Result a)

-- session ids are 16 bytes, and assumed to be random
type SessionId = ByteString

-- options for a connection
data ConnectionOpts
  { sessionTimeout    :: TimeInterval
  , messageTimeout    :: TimeInterval
  , messageRedundancy :: ...
  , ...
  }

openConnection 
  :: ConnectionOpts 
  -> ApplicationProtocol
  -> Either SURB NetworkAddress 
  -> IOResult SessionId

closeConnection :: SessionId -> IOResult ()

-- messages are just blobs of bytes
type Message = [Byte]

-- message indices are just serial numbers 0,1,2...
type MsgIdx = Int

sendMessage :: SessionId -> Message -> IOResult MsgIdx

-- we can poll if a new message was received
--
-- (alternatively, a callback could be installed; 
-- we leave that out here for simplicty)
poll :: SessionId -> IOResult (Maybe Message)

-- we can query the status of the connection
--
-- (eg. number of un-sent messages, un-acknowledged messages 
--  we sent, partially received messages, number of SURBs, etc)
getConnectionState :: SessionId -> IOResult ConnectionStatus

-- we can check whether a sent message was acknowledged by the other party
isAcknowledged :: SessionId -> MsgIdx -> IOResult Bool

-- if we know our expected communication pattern,
-- eg. for example that we want ot receive a large amount
-- of data, then for example we can pro-actively send more 
-- SURBs
provideHints :: SessionId -> Hint -> IOResult ()
```

### How it works

To initiate a connection, we need either a network address, or a SURB to the other party.

SURBs are Mix headers prepared by the other party, which can be used to send them Mix packets without revealing their network address (note though that a patient attacker can always reveal the real IP behind the SURB with some non-negligible probability! So this is only really useful for communication with ephemeral identities...).

A SURB has three components:

- a Sphinx header
- a network address (the first hop in the Mix path, where the packet should be sent)
- and an ephemeral symmetric key (this protects the message against the first hop)

As at least one of the parties want to stay anonymous, they can only receive packets via SURBs. Each SURB can be only used once, hence we need to manage their supply. The main tasks of the transport layer is then to:

- chunk large messages into Mix packets (preferably with some redundancy using erasure coding)
- assemble the received Mix packets back into messages (taking also care of the ordering)
- manage the supply of SURBs, so that ideally they never run out 
- handle acknowledgments and resend lost messages

So, the transport layer needs keep the current state of:

- open connections
- partially received messages
- sent but un-acknowledged messages
- supply of SURBs (if the other party is anonymous)


### Chunking

Given a message $\mathsf{msg}$ of an arbitrary size, we need to chunk it up to uniform sized pieces or "chunks", and send those to the other party via different mix routes (in the payload of mix packets). The other party then needs to recognize these as pieces of the same message, and reconstruct the message (to be processed by the application layer).

As in Mix, we expect some percentage of the packets not arriving the destination, and because the latency is high, we add redundancy by employing [erasure coding](https://en.wikipedia.org/wiki/Erasure_code) together with the chunking, so that any $K$ packets out of the $N$ transmitted packets can reconstruct the message.

Each transport packet will then look like:

- Sphinx header
- Sphinx payload
    - Sphinx integrity check (16 zeros bytes)
    - message metadata:
        - session id (16 bytes, random)
        - message index (4 bytes, sequential numbering)
        - number of original chunks $K$ (2 bytes)
        - total number of redundant chunks $N$ (2 bytes)
    - chunk index (2 bytes; a number `0 <= idx < N`)
    - raw chunk data (fixed size)

Remarks: 

- We use network byte ordering for wire format, that is, numbers are represented as big-endian sequence of bytes.
- We plan to use the [fast erasure coding library `leopard`](https://github.com/catid/leopard/) for EC. This has a limitation of $1 < K < N < 2^{16}$ (and also $N \le 2K$), which justifies using 16 bit numbers for the chunk indices.
- In an ideal world, the total number of (redundant) chunks $N$ wouldn't be necessary to include (as we only need _any_ $K$ packets; an implementation in theory could just generate an infinite stream of new parity chunks); however, this is not true for the Leopard implementation. As the overhead is minimal, maybe it's best to include it (another solution would be a deterministic function $N(K)$; but that's less flexible).
- If the original message fits into a single chunk, we don't do erasure coding; instead if necessary, we just re-transmit it.

#### Payload encoding

To encode and chunk a raw payload (a sequence of bytes):

1. we first prepend a header;
2. then pad it to the next multiple of the raw chunk size $R$ (which is the raw Sphinx payload size minus `42 = 16 + 26 + 2` bytes);
3. split it into $K = \mathsf{length} / R$ pieces;
4. erasure code the pieces into $N$;
5. finally, prepend the chunk header (message metadata and chunk index).

The payload header consists of:

- payload header version number (1 byte)
- length of the raw payload in bytes (8 bytes)
- additional payload info depending on the version

The additional info can be:

- empty (payload version `0x00`)
- SHA256 checksum, truncated to 16 bytes (payload version `0x01`)
- HMAC-SHA256 checksum, truncated to 16 bytes (payload version `0x02`; requires a shared secret between sender and recipient)

Note: Ideally, Mix should provide message integrity. However, if we are paranoid, we can add extra integrity check here.


### Transport message format

The actual messages need to contain not only what the user intends to send (the payload), but also information  needed by the transport layer itself. Hence, a transport message will have three parts:

- administration (eg. acknowledgments)
- fresh SURBs
- the user's payload

The administrative part will contain the following:

- session control
- acknowledgements
- request for fresh SURBs

In Haskell code:

```Haskell
data SessionControl
  = InitialMessage AppProtocol   -- the first message estabilishing a connection
  | Continue                     -- proceed normally
  | CloseSession                 -- closing down the session

data AppProtocol = MkAppProtocol
  { appProtocolName :: String
  , appProtocolInfo :: ByteString
  }

data AckEntry
  = MsgReceived    MsgIdx             -- message received intact
  | MsgFailed      MsgIdx FailReason  -- message failed (eg. decoding, checksum or timeout)
  | NeedMoreChunks MsgIdx ChunkIdx    -- we need more chunks 
  | ResendChunks   MsgIdx [ChunkIdx]  -- re-transmit particular chunks

data FailReason
  = FailTimeout        -- couldn't decode within the expected time
  | FailDecode         -- erasure code decoding failed
  | FailChecksum       -- checksum failed

data MsgMeta = MkMsgMeta
  { msgControl   :: SessionControl   -- where we are in the session
  , msgReqSURBs  :: Int              -- how many more SURBs we need 
  , msgAcks      :: [AckEntry]       -- status of previous messages
  }

data Message = MkMessage
  { msgMeta      :: MsgMeta          -- message metadata
  , msgSURBs     :: [SURB]           -- the new SURBs we send
  , msgPayload   :: ByteString       -- the actual payload
  }
```

#### Wire format

Transport message:

- transport layer version (1 byte; for this version `0x01`)
- session control (1 byte, enum)
- if it was the initial message, then the application protocol:
    - application layer protocol name, as a string (1 byte length, followed by that many bytes)
    - protocol-dependent additional info (4 byte length, followed by that many bytes); can be empty.
- number of fresh SURBs we request (2 bytes)
- acknowledges:
    - number of acknowledge entries (2 bytes)
    - list of acknowledge entries
- fresh SURBs we send:
    - number of SURBs included (2 bytes)
    - the size of a single Sphinx header (2 bytes)
    - list of raw SURBs
- payload

Acknowledge entries:

- entry type (1 byte, enum)
- message index (2 bytes, int)
- depending on entry type value:
   - `0x00 = MsgReceived`: empty
   - `0x01 = MsgFailed`: failure reason (1 byte, enum)      - `0x02 = NeedMoreChunks`: number of chunks requested (2 bytes, int)
   - `0x03 = ResendChunks`:
       - number of chunks to retransmit (2 bytes, int)
       - that many chunk indices (2 bytes each)

SURB entries:

- network address of the first hop
    - address type (1 byte, enum)
    - address length (1 byte, int)
    - followed by that many bytes
- secret key (16 bytes)
- Sphinx header (the length is fixed, and included above for safe parsing)

### State management

The transport layer needs to maintain the state of all "unfinished business", and transparently handle things like acknowledgments, timeouts, re-transmits, etc.

The required state:

- set of open connections (or sessions)
- for each connection:
    - the session id
    - network address (if applicable)
    - the application protocol
    - sent and received message counters
    - set of unused SURBs
    - sent but unacknowledged messages
    - partially received messages
    - outgoing mix packet queue (eg. we may have rate limits or just not enough bandwidth)
- optionally, network quality estimations
    - can be global, per-connection or both
    - estimations for:
        - bandwidth
        - latency
        - packet loss

Then we can describe the expected behaviour via a relatively straightforward (if somewhat complex) state machine.


### Requirements from the Mix protocol

For the above to work, we require some things from the underlying Mix protocol itself:

- ability to query the set of Mix relay nodes (their network addresses and public keys)
- optionally: the ability of generating SURBs and Sphinx headers (but we could also do that ourselves)
- send and receive packets, and handle any rate-limiting 
- a flag _in the Sphinx header_ (inside the destination address field) indicating that this packet is a transport layer packet
- if bidirectional SURBs are used (that is, both sides want to hide their identity), then "SURB proxies" (see below)

#### Sphinx header format proposal

We propose the revise the Mix packet format to better support both this and other use cases, while also being more flexible and potentially also more compact.

Recall that a Sphinx packet consists of:

- ephemeral public key $\alpha$
- encrypted routing info $\beta$
- MAC (authentication code) $\gamma$ of the routing info
- encrypted payload $\delta$

The routing info contains a sequence of `(address, MAC)` pairs, which are address of the next hop and the MAC for the next layer's routing info. The destination address doesn't need the MAC because their is no more info.

In ASCII art:

    beta  = [ Addr1 | MAC1 | Addr2 | MAC2 | Addr3 |  MAC3 | Dest | padding ]
    gamma = MAC0 

We propose that the address field should be variable length, and contain the following data:

- process handling behaviour (enum)
- optional additional info required for the given behaviour 
- if one of the "destination behaviours", then a low-level protocol id (enum)
- address format type (enum)
- if the given address format is variable length (eg. a libp2p address), then its length (1 byte)
- the address itself

Of course the Sphinx header itself needs to have a fixed size, but padding was already necessary because the routing info for different layers have different sizes anyway. So this only means that we can fit more hops if the addresses are shorter.

Example address formats:

- IP address (fixed length)
- libp2p address (variable length)
- compressed Mix node address (fixed length; a truncated hash of the Mix public key)

Example packet processing behaviours:

- you are a normal Mix relay, remove one layer and forward as usual
- you are the destination, and it was a forward message
- you are the destination, and it was a reply message (sent via SURB). The address field also contains a unique ID of the SURB.
- you are the destination, and it was a proxied replay message (sent via SURB by a proxy, see below for details; this requires different payload handling)
- you are an exit relay; decrypt and forward to an "external" address
- you are a SURB proxy; forward using the proxy behavour

Example of destination protocols:

- default Mix protocol
- transport layer protocol
- exit node protocol (the final destination is "external")

#### SURB proxies

SURBs are more-or-less "safe" for the SURB _creator_, but they are _extremely unsafe_ for the _user_ of the SURB: The SURB creator can trivially figure out their identity simply by putting a mix node under their control as the first hop.

A mitigation against this is that both parties control "their side" of a path, meeting in the middle, similar to Tor randevuous points.

As Sphinx headers can be created only in one direction, this means that the (randomly selected) randevous point needs to extract a SURB and encrypted payload, and use those to forward to the final destination. This way it's the randevous point whose identity the attacker could find out, but that's just a random Mix node.

In more details: 

Suppose we use 3 hops, and party `A` wants to send a packet to party `B` via a SURB prepared by party `B`.

Party `A` prepares a special payload, which wrap both the SURB and the actual payload (hence the actual payload must be smaller than the usual payload). It then selects a random path of 4 hops, and prepares a Mix header with the destination being _the 4rd hop_, and a destination processing behaviour indicating that it's a SURB proxy.

In ASCII art:

          A -> a1 -> a2 -> a3 -> P => b1 -> b2 -> b3 -> B
               \_________________/    \_________________/
                    A's path               B's SURB

When the Mix node `P` (for proxy) receives and decrypts the packet, they see the flag indicating that it's a special proxy packet and they need to proxy it. They thus decode the payload into the SURB and the smaller payload; pad the smaller payload; and use the extracted SURB to send the padded payload to `b1` (whose address is part of the SURB).

When `B` receives the final packet, they will see another flag in the payload, indicating that it was proxied. This is necessary because it needs to be decrypted differently (?). And `A` cannot put it into header, because the header was prepared by `B`...

