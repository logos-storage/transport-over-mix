Sphinx packet format
====================

Sphinx is concrete packet format for mixnets, with the following goals:

- compact (small overhead over the payload)
- hiding the path length and relay position
- unlinkability between the legs
- indistinguishability of forward and reply packets
- provable security

The main trick Sphinx achieves compactness is re-using a single public key (via a blinding mechanism) for each leg.

#### Links

- the [Sphinx paper](https://cypherpunks.ca/~iang/pubs/Sphinx_Oakland09.pdf)
- a [nice talk on youtube](https://www.youtube.com/watch?v=34TKXELJa2c) about Sphinx

### Security parameters

We denote the intended security level by $\lambda$ as usual. By default we target $\lambda=128$ bits of     security. Hence:

- private keys are of size $p = 2\lambda$, that is, 32 bytes
- as we use elliptic curve groups, public keys are the same size
- symmetric keys are size $s=\lambda$, that is, 16 bytes
- MACs are also of size $\lambda$, that is, 16 bytes

A further parameter is maximum number of hops (as all packets need to have the same size, you need to pre-agree on this). This is denoted by $r$, and a good recommended default value is $r = 5$.

#### Elliptic curve

For public key cryptography, we use elliptic curves as they are compact (unlike for example RSA), and also conceptually simple.

We denote the elliptic curve group by $\mathbb{G}$, its fixed generator by $\mathbf{g}\in \mathbb{G}$, and the corresponding scalar field by $\mathbb{F}_q \cong \mathbb{Z}_q$. The elliptic curve scalar multiplication is denoted by $*:\mathbb{Z}_q \times \mathbb{G} \to \mathbb{G}$.

The standard curve choice is [Curve25519](https://en.wikipedia.org/wiki/Curve25519).

#### Symmetric primitives

- we will need a MAC; the standard choice is HMAC-SHA256 truncated to $\lambda=128$ bits
- we will need a (set of) key derivation function(s) $\mathsf{KDF}$. A standard choice is SHA256 with a domain separation; eg. $\mathsf{KDF}_{\mathsf{MAC}}(x):=H(\texttt{"MAC"}\|x)$, truncated as necessary
- we need a pseudo-random stream generator, which will be used to encrypt the routing information. Usually this is AES128-CTR (that is, AES in [counter mode](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation#CTR)), but it could be also a XOF like SHAKE128. Below we will denote this by $\mathsf{XOF}(k)$ where $k$ is the key.
- we also need a pseudo-random permutation (sometimes called a "large block cipher") to encrypt the payload. In particular, one **SHOULD NOT USE** a standard block cipher in counter mode for this. Note: This is kind of tricky, see more about this below.
 
Remark: While this is what the original Sphinx paper needs, there may be tweaks of the design, using more modern symmetric primitives, eg. AEAD to replace the problematic pseudo-random permutation. See below, near the bottom.

## Packet format

A Sphinx packet consists of four parts, traditionally denoted by $\alpha$, $\beta$, $\gamma$, and $\delta$:

- $\alpha$ is a (blinded) public key (group element; $\alpha\in\mathbb{G})$.
- $\beta$ is the (encrypted) routing information
- $\gamma$ is a MAC (message authentication code)
- $\delta$ is the (encrypted) payload

The first three of these, $\mathcal{H}=(\alpha,\beta,\gamma)$ is called the header.

Observation: Because we need to allow for the user to create reply paths in advance (SURBs, or single-use reply blocks), where the payload is not yet known, we cannot use traditional "onion" encryption; instead, the header and the payload must be separate. However, the payload will be still encrypted in several layers, and its integrity is protected (if implemented properly).

### Constructing a packet

First, the user selects a random path of mix nodes $n_0,\dots n_{\ell-1}$ with $\ell\le r$. We will also need a final destination $\Delta_\mathrm{final}$; and in case of replies, a message identifier $J$. 

#### Computing the shared secrets

We assume all mix nodes have a long-term private-public keypair $(\mathsf{sk}_i,\mathsf{pk}_i)$.

The user first generates an ephemeral secret key $x$; in practice this is just a random number $x\in\mathbb{Z}_q^\times$. It can then iteratively derive a sequence of keys (one set per hop) consisting of:

- a per-node secret key $x_i\in\mathbb{Z}_q^\times$
- a per-node public key $\alpha_i:=x_i*\mathbf{g}\in \mathbb{G}$
- a per-node shared secret $s_i\in \mathbb{G}$, derived using  Diffie-Hellman: $s_i:=x_i*\mathsf{pk}_i = \mathsf{sk}_i*\alpha_i$
- a blinding factor $b_i\in\mathbb{Z}_q^\times$, computed from $\mathsf{KDF}_{\mathsf{blind}}(\alpha_i,s_i)$ 

Remark: The blinding factor is supposed to be in $\mathbb{Z}_q^\times$ (recall that $q\approx 2^{256}$). We can ensure this either by simply taking it modulo $q$, or more properly by rejection sampling a deterministic sequence. Implementations however usually simply say $b_i:=H(\alpha_i,s_i)$ where $H$ is eg. SHA256. Same care should be taken in an actual implementation to avoid possible corner cases.

The key sequence is defined iteratively:

- $x_0:=x$
- $x_{i+1}:=b_i\cdot x_i$

All the rest can be computed from $x_i$:

- the public key is $\alpha_i = x_i * \mathbf{g}$
- the shared secret is $s_i=x_i*\mathsf{pk}_i$ 
- and the blinding factor is $b_i=H(\alpha_i,s_i)$

The idea behind this construction is that each hop will have a unique sender public key, from which a shared secret can be derived, and then further symmetric keys for MAC and encryption via a KDF. When composing the forwarded packet for the next hop, the node can then "tweak" this public key using their own blinding factor: $\alpha_{i+1}=b_i * \alpha_i$. 

Thus each hop can only decrypt their own header, and if they try to break the protocol, the message will be ruined.

#### Fillers (header padding)

In layered, "onion" routing, each node removes a layer of encryption, and forwards the resulting payload. Done naively, this would result both the headers and the packets to decrease in size while travelling through the mix path. This is obviously bad; we need to ensure the headers are of uniform size.

However, we also need to ensure that at all hops, the processing of the header and payload is exactly the same (otherwise nodes could figure out where they are in the path). These requirements result in the following, somewhat convoluted construction.

The filler strings $\phi_i \in \{0,1\}^{2\lambda i}$ are also constructed iteratively:

- $\phi_0$ is the empty string
- to construct $\phi_{i+1}$, take $\phi_i$, append $2\lambda$ zero bits (in our case, 32 zero bytes), and XOR the resulting string with the last $2\lambda (i+1)$ bits of the (fixed size) random stream derived from the shared secret $s_i$:

$$
\begin{align*}
  e_i &:= \mathsf{KDF}(\texttt{"route-enc-key"}\|s_i) \\
  \widetilde\phi_{i+1} &:= [\,\phi_i \;\|\; 0^{2\lambda}\,] \\
  \phi_{i+1} &:= \widetilde\phi_{i+1} \;\oplus\; \mathsf{XOF}(e_i)_{\rho\dots \rho+2\lambda (i+1)}
\end{align*}
$$

where the offset is $\rho = (2r+3)\lambda - 2\lambda (i+1)$. Note: We use the convention that a tilde denotes the unencrypted version.

One reason for all this complication is that the headers are constructed _backwards_, but the fillers must be constructed _forwards_. Furthermore, we also need to replace truncated bits while processing and forwarding mix packets; that's why we have the $2\lambda$ zero bits at the end (it could be any constant, zero is just the simplest).

#### Constructing the header

We now want to construct the initial message header $\mathcal{H}_0=(\alpha_0,\beta_0,\gamma_0)$. This needs to encode the routing information in encrypted layers. So, we will do it iteratively, backwards from the last hop's header $\mathcal{H}_{\ell-1}=(\alpha_{\ell-1},\beta_{\ell-1},\gamma_{\ell-1})$. 

Sidenote: In the paper these headers are denoted by $M_i$, but that's a bit confusing as the reader could think "message" instead.

Apart from the mix path, we also require a destination address $\Delta$, and message identifier $J\in\{0,1\}^\lambda$. These are only used in replies ($\Delta$ would be our address, and $J$ is to identify the reply among several); they don't seem to play a role in forward messages (apart from detecting being the exit node). The destination $\Delta$ must fit into $2\lambda (r-\ell+1)$ bits; for $r=\ell$ this means $2\lambda$ (32 bytes), and to simplify we will assume that, ie. $\Delta\in\{0,1\}^{2\lambda}$.

Remark: In the Logos implementation, $\Delta$ is actually somewhat bigger (but still bounded), ~~48~~ 96 bytes (?). It's relatively straightforward to generalize this construction to allow for that (though 96 bytes instead of 16 is very wasteful, as it's get multiplied by the maximum number of hops $r=5%...).

- $\alpha_i\in\mathbb{G}$ is just the per-hop public key computed above
- $\beta_i \in \{0,1\}^{(2r+1)\lambda}$ is the layer-by-layer encrypted routing information
- $\gamma_i \in \{0,1\}^\lambda$ is the MAC of $\beta_i$, computed with a mac key derived from the shared secret $s_i$

Question: Why isn't $\alpha_i$ also included in the MAC? I guess it's not really necessary, as if $\alpha_i$ is tampered with, then decryption and everything else will fail?

We will need several symmetric keys, all of size $\lambda$; these are all derived from the shared secret:

- $m_i := \mathsf{KDF}(\texttt{"mac-key"}\;\|\;s_i)$ is the MAC key
- $e_i := \mathsf{KDF}(\texttt{"route-enc-key"}\;\|\;s_i)$ is the key use to encrpytion the routing info 
- $\mathrm{V}_i := \mathsf{KDF}(\texttt{"iv"}\;\|\;s_i)$ is the initialization vector (when using AES or some other block cipher as our PRG stream generator)

Then we construct the headers iteratively:

- $\widetilde\beta_{\ell-1} := [\,\Delta \;\|\; J \;\|\; 0^{2(r-\ell)\lambda} \;\|\; \widetilde{\phi}_{\ell-1} \,]$
- $\widetilde\beta_{i-1}:= [\, A_i \;\|\; \gamma_i \;\|\; \mathsf{trunc}_{(2r-1)\lambda}(\beta_i) \,]$
- $\beta_i := \widetilde\beta_i \oplus \mathsf{XOF}(e_i)$
- $\gamma_i := \mathsf{MAC}_{m_i}(\beta_i)$

where $A_i\in\{0,1\}^\lambda$ (only 16 bytes, unlike $\Delta$!) is the address of the $i$-th node in the path. Note: When computing $\beta_{i-1}$, the $\beta_i$ coming from the next hop is truncated (the last $2\lambda$ bits is discarded), so that's where the address and MAC fits in. This is not a problem because as we remove the layers, less and less routing information is required; the actual useful content of the final header is only $(\Delta,J)$.

It's useful to have a picture of the sizes of the various components here:

- $|\Delta| = 2\lambda$
- $|J| = |\gamma_i| = \lambda$
- $|\phi_i| = 2\lambda i$
- $|\beta_{\ell-1}| = 3\lambda + 2(r-1)\lambda = (2r+1)\lambda$
- $|A_i| = \lambda$
- $|\beta_i| = 2\lambda + (2r-1)\lambda = (2r+1)\lambda = |\beta_{\ell-1}|$

#### Creating a forward message

Let the message to be sent be $\mathtt{msg}\in\{0,1\}^N$, and the final destination (the intended receiver) by $\Delta_{\mathrm{final}}\in\{0,1\}^{2\lambda}$. Note: $N$ must be a constant, so that each packet has the same size.

The header $\mathcal{H}_0$ is computed as above, setting $\Delta=0^{2\lambda}$ and $J=0^{\lambda}$. We also need the per-hop shared secrets $s_i$. From these, we calculate the payload encryption keys:

$$
k_i := \mathsf{KDF}( \texttt{"payload-key"} \; \| \; s_i)
$$

Now we can compute the encrypted payload iteratively:

- $P:=[\,0^\lambda\;\|\;\Delta_{\textrm{final}}\;\|\;\mathtt{msg}\,]$
- $\delta_{\ell-1} := \mathsf{ENC}(\,k_{\ell-1};\; P )$
- $\delta_{i-1} := \mathsf{ENC}(\,k_{i-1};\; \delta_i )$

The final packet is $(\alpha_0,\beta_0,\gamma_0,\delta_0)$. 

This has size $2\lambda+(2r+1)\lambda+\lambda+(3\lambda+N) = N + (2r+7)\lambda$. So for the default parameter $\lambda=128$ and $r=5$, the overhead is $17\times 16 = 272$ bytes (the header being $224$ bytes and the integrity check + destination $16+32 = 48$ bytes).

#### Creating a reply message

First, the original sender creates a SURB (single use reply block). To do this, they first pick a random path $A_0,\dots,A_{\ell-1}$ and compute a message header $\mathcal{H}_0$ as above, with $\Delta$ being their own address (though technically it could be somebody else too), and $J$ a random message identifer.

Pick a random symmetric key $K\in\{0,1\}^\lambda$, and save the following key mapping in some local table:

$$
J \mapsto (K,k_0,\dots,k_{\ell-1})
$$

where the encryption keys $k_i = \mathsf{KDF}( \texttt{"payload-key"} \| s_i)$ are the same as above.

The SURB is the triple

$$ \mathsf{SURB} := (A_0,\mathcal{H}_0,K)$$

This has the size $(2r+6)\lambda$, in our case 256 bytes.

To compose a reply message using a SURB, the sender encrypts their payload $\mathtt{reply}\in\{0,1\}^{(N+2\lambda)}$ into $\delta := \mathsf{ENC}(K;\, [0^{\lambda} \,\|\, \mathtt{reply}])$ and sends the packet $(\mathcal{H}_0,\delta)$ to the node with address $A_0$.

## Processing mix packets


Upon receiving a mix packet, a node should do the following:

0. check the packet size to conform the expected fixed size, and split it into $(\alpha,\beta,\gamma,\delta)$
1. check if the first 32 bytes correspond to a valid group element $\alpha\in\mathbb{G}$ (apparently this is a no-op for Curve25519)
2. compute the shared secret $s = x*\alpha \in \mathbb{G}$, where $x\in \mathbb{Z}_q^\times$ is our long-term secret key 
3. check if this shared secret was seen before by looking up it's hash $H(s)$ in a table we keep. Reject if it was seen before.
4. recompute the MAC of $\beta$ using the derived MAC key $m_i=\mathsf{KDF}(\texttt{"mac-key"}\|s)$, and compare it with $\gamma$. Reject if they differ
5. decrypt the routing info $B:=\mathsf{DEC}(e_i;\,[\beta\|0^{2\lambda}])$ using the derived encryption key $e_i=\mathsf{KDF}(\texttt{"route-enc-key"}\|s)$
6. Parse the address in the first $\lambda$ bits of $B$: If it's all zeros, then we are the exit node of a forward message. If it's an address of a mix node, then we have to forward. Otherwise we are the exit node of a reply message, and this address is the recipient.
8. Remove a layer of encryption from the payload $\delta' := \mathsf{DEC}(k;\, \delta)$ using 
the payload encryption key $k := \mathsf{KDF}( \texttt{"payload-key"} \| s)$

If we are the exit node of a forward message:

- Check if the first $\lambda$ bits of $\delta'$ are zero. Reject if not
- Extract the destination address $\Delta$ from the payload (bits $[\lambda\dots (3\lambda-1)]$ of $\delta'$)
- If it looks like a valid network address, send them the remaining payload

If we are the exit node of a reply message:

- It's basically the same as above, except that we also need to extract $J$ and send it together with the payload
- We also don't have to remove the $\Delta$ piece from the payload (as it's not there)
 
If we have to forward it:

- compute the blinding factor $b = \mathsf{KDF}_{\mathsf{blind}}(\alpha,s)$
- compute $\alpha' = b * \alpha\in\mathbb{G}$
- let $\gamma'$ be the second $\lambda$ bits of $B$
- let $\beta'$ be the remaining bits of $B$ (recall that before decrypting $\beta$, we appended $2\lambda$ zero bits; thus $\beta'$ is the right size!)
- forward $(\alpha',\beta',\gamma',\delta')$ to the next mixed node, whose address was in the first $\lambda$ bits of $B$

#### Decrypting replies

Unlike forward message payloads, replies are encrypted; see above. (Of course the sender can encrypt the forward messages themselves, eg. if they know a public key or shared secret with the intended recipient).

To decrypt, the recipient should look up the message id $J$ in their local table, and find the $\ell+1$ symmetric keys $(K,k_0,\dots,k_{\ell-1})$.

The recipient of the reply message can decrypt the payload $\delta$ with

$$
\mathsf{DEC}(K;\; \mathsf{ENC}(k_0;\; \mathsf{ENC}(k_1;\;
\dots \mathsf{ENC}(k_{\ell-1};\;\delta)\dots)))
$$

If the first $\lambda$ bits after decryption are zero, then message is consired valid.

### Message integrity

A subtle part of this protocol is message integrity. 

This is ensured by prepending $\lambda$ zero bits to any payload, and using a "large block cipher", or pseudo-random permutation (PRP) to encrypt the payload in layers:

$$\pi : \{0,1\}^\lambda \times \{0,1\}^{N+3\lambda} \to \{0,1\}^{N+3\lambda} $$

This means that $\pi(k)$ should be indistinguishable from a random permutation (of $2^{N+3\lambda}$, so not permuting _the bits_, but permuting _all possible payloads_!)

Encryption and decryption is then simply

$$
\begin{align*}
\mathsf{ENC}(k;\delta) &:= \pi(k)(\delta) \\
\mathsf{DEC}(k;\delta) &:= \pi^{-1}(k)(\delta) 
\end{align*}
$$

With such a construction, if any single (or more) bit(s) of the payload is flipped, then after applying the permutation, the whole ciphertext should be uncorrelated with the unmodified one. This means that if somebody tries to modify the payload in route, at the end the bits which are supposed to be zeros won't be.

In particular, this most assuredly _doesn't work_ for AES-CTR or any other block cipher in counter mode!

While AES itself is a pseudo-random permutation, it can only permute blocks of fixed size, namely 128 bits. That unfortunately isn't helpful here.

#### Possible choices for a PRP

While an arbtirary sized PRP is a very powerful building block, there appears fewer choices than for block ciphers.

- the paper recommends LIONESS; see the paper ["Two practical and provabliy secure block ciphers: BEAR and LION"](https://www.cl.cam.ac.uk/archive/rja14/Papers/bear-lion.pdf). These are built using the [Luby-Rackoff construction](https://omereingold.wordpress.com/wp-content/uploads/2014/10/lr.pdf)
- see also [this paper](https://arxiv.org/abs/1105.0259) on the security of these schemes
- [AEZ](https://web.cs.ucdavis.edu/~rogaway/aez/aez.pdf) appears to have an arbitrary-sized block cipher, and should be fast, but I find the paper hard to decipher, and probably has less analysis.
- see the paper ["Improving the Sphinx Mix Network"](https://www.bartmennink.nl/pubs/16cans.pdf) about modifying the Sphinx construction to use alternative symmetric constructions (eg. AE) (???)
 
### Variations

The above is basically what is described in the Sphinx paper. But for different use cases, some modifications could be useful.

#### Larger address size

Logos Mix is built on top of libp2p, so the natural address format is libp2p addresses. These are apparently not just an IP address, port number and protocol selector (eg. TCP, UDP, Quic), but also include a ["PeerID"](https://github.com/libp2p/specs/blob/master/peer-ids/peer-ids.md) (here limited to 39 bytes, but in general it could be longer). Furthermore, a suggested average delay is also encoded in the address field. 

In any case, because of the PeerID this doesn't fit into 32 bytes, but just fits into 48 bytes.

Let allow an address size of $t\times \lambda$, for both mix nodes and final destination (with $t\ge 2$). In this case, the pieces change like this:

- $|\Delta|=|A_i|=t\lambda$
- $|\phi_{k}| = (t+1)k\lambda$
- $|\beta_{k}| = (t+1)r\lambda$

The total overhead is the sum of $2\lambda$ (the group element $\alpha$), $(t+1)r\lambda$ (the routing info $\beta$), $\lambda$ (the MAC), and $(t+1)\lambda$ (the final destination address and the integrity check).

In total thats $((t+1)(r+1)+3)\lambda$. For the Logos choice of $t=3$ and $r=5$, this would mean 432 bytes.

TODO: double-check this!

#### Mix nodes as recipients

We imagine that sometimes our recipients will be also mix nodes themselves. This probably requires a slight modification of the exit node handling.

TODO

#### Alternative symmetric cryptography

TODO

## Differences between the paper and Logos Mix

There are some deviations from the above in the Logos [Mix specification](https://lip.logos.co/ift-ts/raw/mix.html).

- they use AES128-CTR to encrypt the payload. This completely breaks message integrity.
- they use a larger address space than $2\lambda$ for both the destination and mix addresses $\Delta$ and $A_i$ (96 bytes at the times of writing this, which is $2 \times 48$ bytes to allow for libp2p relay circuits)
- ...

