Transport layer abstraction over Mix
------------------------------------

Mix supports the following basic communication pattern:

- sending a fixed size packet (approx 4kb) to someone with a public IP address, but hiding the sender's identity 
- optionally (?) getting back a reply of the same size (via a SURB)

This is not enough for many (most?) real-world use cases:

- we want to send larger messages
- we want to get back larger replies
- we may want "acknowledge" messages when the full larger message is received intact
- some form of message integrity check would be useful
- we may not know the size of reply a priori
- we may want to allow the reply being a stream
- we may want to get back multiple, time-separated replies
- we may want socket-like behaviour
- as Mix is expected to lose at least a small fraction of packets, it would be nice to have some built-in fault-tolerance

While mix already has very rudimentary support for chunking up an outgoing message, it doesn't yet support all these more sophisticated use cases.

Our suggestion is to build an "application-level" transport abstraction layer to handle all the above.

### Basic workflow

The basic workflow of how something like this could work is pretty straightforward:

1. The user wanting to communicate with a remote party first generates a unique (random?) session id
2. The user takes their message payload, generates a number of SURB paths, and bundles the message and the SURBs into a single bytestring, from which the list of surbs, the payload, and the message type ("initial payload") can be reconstructed. 
3. A checksum of this extended payload is added
4. The user erasure codes this bytestring into uniform chunks (of the maximum mix packet size minus a fixed header), with a configurable overhead (eg. 10% extra size for redundancy)
5. For each erasure coded chunk, a header consisting of the session id, a message sequence number (eg. 1st message in a socket-like abstraction), an EC chunk index, and the erasure coding parameters are prepended.
6. The resulting extended chunks are sent over Mix using different paths

Now on the receiver side:

1. The receipent starts to get some of the above mix packets
2. They need to identify that the packets are sent according this protocol. This should be probably encoded in the Mix final destination address (eg. it could be in the destination protocol byte?)
3. After identified as such, as each decoded packet contains the session id and message sequence number, they can put them into buckets according to those
4. As each of those also includes the erasure coding parameters, they know when enough packets arrived for decoding
5. Each EC chunk also include their chunk index, so they can decode the original extended payload
6. They can check integrity be recomputing and comparing the checksum 
7. Parse the extended payload into the original message, message type, and set of SURBs
8. Do whatever they want the payload, and reply using the the above (sender) protocol, but using the SURBs 

Note that maybe there aren't enough SURBs to send the reply. In this case, they can construct a partial reply, which also include a request for more SURBs. The encoding of this must be also standardized.

While the original sender doesn't need SURBs for themselves, because they know the receiver's IP address, this situation will change when we also introduce hidden services, so both parties are anonymous. For this reason, it's better to make the package formats symmetric from the start, and include the request for more SURBs in the initial message too (but it can be set to zero).

### Mix abstraction

At first approximation, we assume the following things from Mix:

- Mix can deliver fixed sized packets (of size `M` bytes, where `3072 <= M < 65536` is relatively small) to some destination address (which can be an IP address or later maybe a pseudonymous identity)
- a destination address can also be a SURB, which we just assume an opaque blob of say `S <= 512` bytes.
- users can generate an arbitrary number of fresh SURBs, whose final destination is themselves
- packet delivery is not guaranteed (but expected with some probability, eg. 95%)

Note that in practice, Mix may provide some other guarantees, eg. message integrity (except that the implementations may mess that up...). 

We also assume that the destination server also has a public key.

### Abstract data encoding

We use Haskell syntax to specify our data structures.

    -- what the parties want to actually send
    type Payload = ByteString
    
    -- we use an ephemeral public key as the session id
    type SessionId = PublicKey
    
    -- message sequence inside a session
    type SequenceNumber = Int
    
    type ChunkIdx = Int
    
    -- the erasure coding algorithm 
    -- encodes K chunks into N chunks
    data ECParams = MkECParams 
      { ecK :: Int
      , ecN :: Int
      }
    
    -- we assume fixed size of `S` bytes
    type SURB = ByteString
    
    data Destination
      = IPAddress String
      | SingleUse SURB
      | Pseudonym PublicKey
    
    data MessageType
      = IntialMsg
      | FinalReply
      | Streaming      -- ??
      ... 
      
    data ExtendedPayload = MkExtPayload
      { msgType      :: MessageType 
      , requestAck   :: Bool
      , requestSurbs :: Int
      , surbs        :: [Surb]
      , payload      :: Payload
      }
      
    type CheckSum = HMAC
    
    type ECChunk = ByteString
    
    data ExtendedChunk = MkExtChunk
      { sessionId :: SessionId
      , seqNum    :: SequenceNumber
      , chunkIdx  :: ChunkIdx
      , ecParams  :: ECParams
      , chunk     :: ECChunk
      }
    
    
### Concrete encoding (wire format)

