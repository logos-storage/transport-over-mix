Abstract Sphinx Description
---------------------------

It turns out that if we abstract away the details, and consider addresses to be just arbitrary data, describing the Sphinx packet construction becomes much simpler and more intuitive (and also more general).

### Security parameters

Let $\lambda=128$ be the targeted security level in bits, and $\kappa = \lambda/8 = 16$ the same but measured in bytes.

Let $r\in\mathbb{N}$ denote the maximum number of hops, and $1\le\ell\le r$ the actual number of hops (mix nodes in the path).

### Sphinx packets

A Sphinx packet is a pair $(\mathcal{H},\delta)$ where $\mathcal{H}=(\alpha,\beta,\gamma)$ is the header, and $\delta$ is the (encrypted) payload. Each of the four component of the packet must be constant size: $|\alpha|=2\kappa$, $|\beta|=N_\beta$, $|\gamma|=\kappa$, and $|\delta|=N_\delta$. For example, if we have 16-byte mix node addresses and 48 byte destination addresses, then $N_\beta=176$ bytes, and thus the overhead of the header is $|\mathcal{H}|=224$ bytes.

The header construction is the interesting part; the payload is simply encrypted in multiple layers, each hop removing (or adding, in case of reply messages) one layer of encryption.

#### Message integrity

Note: Since for reply messages we need to create the headers before the actual message payload is known (resulting in SURBs, "Single Use Reply Blocks"), the header and the payload are handled separately. 

This is a problem because if header and payload are decoupled, how to guarantee message integerity? Sphinx solves this rather elegantly: The payload MUST be encrypted using a so-called pseudo-random-permutation (PRP):

$$
\pi \;:\; K\times \{0,1\}^{N_\delta} \;\to 
\{0,1\}^{N_\delta}
$$

which is practically indistinguishable from a random permutation. In particular, even if a single bit of the input is flipped, one would expect approximately half of the bits flip in the output - it should completely scramble the input. The original Sphinx paper recommends using the Lioness "wide-block cipher" for this purpose (with the whole payload consisting a single "wide" block!).

Then, if the payload is prepended by $\kappa$ zero bytes, if any mix node (or middle-man) tries to tamper with it, the final decrypted payload will have $2^{-128}$, that is, negligible chance for these zero bytes to reaming intact.

### Computing the shared secrets

Sphinx uses layered encryption while the packet travels through the mix network; for this we need to derive a (different) shared secret for each mix node.

We assume all mix nodes have a (relatively) long-term private-public keypair $(\mathsf{sk}_i,\mathsf{pk}_i)$. Note: In practice, these keys are usually rotated with some frequency, which can be for example daily, weekly or monthly; but we assume we know the relevant public keys.

The user creating the header first generates an ephemeral secret key $x$; in practice this is just a random number $x\in\mathbb{Z}_q^\times$. It can then iteratively derive a sequence of keys (one set per hop) consisting of:

- a per-node secret key $x_i\in\mathbb{Z}_q^\times$
- a per-node public key $\alpha_i:=x_i*\mathbf{g}\in \mathbb{G}$
- a per-node shared secret $s_i\in \mathbb{G}$, derived using  Diffie-Hellman: $s_i:=x_i*\mathsf{pk}_i = \mathsf{sk}_i*\alpha_i$
- a blinding factor $b_i\in\mathbb{Z}_q^\times$, computed from $\mathsf{KDF}_{\mathsf{blind}}(\alpha_i,s_i)$ 

Remark: The blinding factor is supposed to be uniform in $\mathbb{Z}_q^\times$ (recall that $q\approx 2^{256}$). However it's not a big deal if it's a little bit bigger, or if there is a tiny bias from uniformity; hence implementations however usually simply say $b_i:=H(\alpha_i,s_i)\in [0,2^{256}-1]$ where $H$ is eg. SHA256. Same care should be taken in an actual implementation to avoid possible corner cases (?).

The secret key sequence is then defined iteratively:

- $x_0:=x$
- $x_{i+1}:=b_i\cdot x_i$

All the rest can be computed from $x_i$:

- the public key is $\alpha_i = x_i * \mathbf{g}$
- the shared secret is $s_i=x_i*\mathsf{pk}_i$ 
- and the blinding factor is $b_i=H(\alpha_i,s_i)$

The idea behind this construction is that each hop will have a unique ephemeral sender public key, from which a shared secret can be derived, and then using a KDF further symmetric keys are derived from that ($m_i$ for MAC, $e_i$ for header encryption and $p_i$ for payload encryption). When composing the forwarded packet for the next hop, the node can then "tweak" this public key using their own blinding factor: $\alpha_{i+1}=b_i * \alpha_i$. 

Thus each hop can only decrypt their own header, and if they try to break the protocol, the message will be ruined.

Sidenote: With X25519, not all 32-byte integers are valid secret keys. However, we cannot simply apply the standard "masking" algorithm to the  blinded private key, because the mix nodes doing the processing won't have access to the secret keys. At least the cofactor 8 subgroup is kept invariant by multiplication. I think that the remaining of the mask is only there to ensure uniformity of randomly generated secret keys; so this is probably still OK at the end.

### Sphinx headers

A Sphinx header $\mathcal{H}$ consist of a triple $\mathcal{H}=(\alpha,\beta,\gamma)$, where

- $\alpha$ is a (blinded) public key (that is, a group element; $\alpha\in\mathbb{G})$.
- $\beta$ is the (encrypted) routing information
- $\gamma$ is a MAC (message authentication code) of $\beta$

The header must have a fixed size of $N_{\mathcal{H}}$ bytes. As $|\alpha|=2\kappa$ and $|\gamma| = \kappa$, we have $N_{\mathcal{H}} = N_{\beta} + 3\kappa$, where $N_\beta := |\beta|$ is the size of the encrypted routing info.

Let $(A_0,A_1,\dots,A_{\ell-1},A_\ell=\Delta)$ be a mix path of length $\ell$, that is, a sequence of $\ell+1 \le r$ generalized addresses. $A_0$ is the "entry node", the mix node we will send the packet to; $A_{\ell-1}$ is the "exit node", the final mix node; and $A_\ell=\Delta$ is the final destination. These can have different types and even different sizes, as long as: 

- they are prefix-parseable
- the total size fits in the header

The routing information $\beta:=\beta_0$ will contain the sequence of addresses and MACs:

$$(A_1,\gamma_1,A_2,\gamma_2,A_3,\gamma_3,\;\dots\;, A_{\ell-1},\gamma_{\ell-1},A_{\ell})$$

but encrypted in several layers (note that there is one less MAC than addresses!). The first address $A_0$ we directly send to, and the first MAC $\gamma_0$ is stored in the "$\gamma$" section of the header (while the above sequence is encoded in "$\beta$", the routing piece).

Hence the size condition means that:

$$
\underbrace{(\ell-1)\kappa}_{\textrm{MACs}} \;+\; \underbrace{\sum_{i=1}^{\ell} |A_i|}_{\textrm{addresses}} \;\;\le\;\; N_\beta \;=\; N_\mathcal{H} - 3\kappa
$$

that is,

$$
\sum_{i=1}^{\ell} |A_i| \; \le \; |\mathcal{H}| - (\ell+2)\kappa
$$

Apart from this, we have no restriction on the addresses.

### Constructing Sphinx headers

We construct a Sphinx header iteratively, going backwards from the last hop.

The routing info for the final hop is 

$$ 
\beta_{\ell-1} := \mathsf{encdec}_{\ell-1} \big(\, \Delta \;\|\; 0^{\mathrm{pad}} \,\big) \;\big\|\; \phi_{\ell-1} 
$$

where $\Delta = A_\ell$ is the final destination; 

$$\mathsf{encdec}_{i}(x)\;:=\; x \oplus \mathsf{STREAM}(e_i)$$ 

is a XOR-based stream cipher using the encryption key $e_i$ derived for the $i$-th hop; and $\phi_{\ell-1}$ is a "filler string", to be defined below. Note that the filler string is _not encrypted_ (in fact it will be encrypted, but using the previous key $e_{\ell-2}$). The required padding length can be then computed easily as $\mathrm{pad} := N_\beta - |\Delta| - |\phi_{\ell-1}|$.

The header of the final hop will be then simply $\mathcal{H}_{\ell-1} = (\alpha_{\ell-1}, \beta_{\ell-1}, \gamma_{\ell-1})$ where $\gamma_{\ell-1}:=\mathsf{MAC}_{\ell-1}(\beta_{\ell-1})$ is the MAC of $\beta$ (using the corresponding MAC key).

To construct an earlier header $i<\ell-1$, we can form

$$ 
\beta_{i} := \mathsf{encdec}_{i}\big[\, A_{i+1} \;\|\; \gamma_{i+1} \;\|\; \mathsf{trunc}(\beta_{i+1}) \,\big]
$$

where $\mathsf{trunc}()$ simply truncates to the required length $N_\beta - |A_{i+1}| - |\gamma_{i+1}|$.

As before, then $\gamma_{i} := \mathsf{MAC_{i}}(\beta_{i})$ is the corresponding MAC, and then the header is $\mathcal{H}(\alpha_i,\beta_i,\gamma_i)$.

### Filler strings

Expanding the above construction, the routing info $\beta$ in the intitial header looks like this (see also the illustration below):

$$
\beta_0 = 
\mathsf{E}_0\Big[ A_1 \big\| \gamma_1 \big\| 
\mathsf{E}_1\Big[ A_2 \big\| \gamma_2 \big\|
\mathsf{E}_2\Big[ A_3 \big\| \gamma_3 \big\| \cdots 
\mathsf{E}_{\ell-1}\Big[ \Delta \big\| \mathsf{pad} \Big]\cdots \Big]\Big]\Big]
$$

where we use the shorthand $\mathsf{E}_i:=\mathsf{encdec}_i$ so that it fits into a line.

However, when this get processed by the first mix node (with address $A_0$), the first layer of encyption and also the address and MAC $A_1,\gamma_1$ are removed, resulting in:

$$
\beta'=
\mathsf{E}_1\Big[ A_2 \big\| \gamma_2 \big\|
\mathsf{E}_2\Big[ A_3 \big\| \gamma_3 \big\| \cdots 
\mathsf{E}_{\ell-1}\Big[ \Delta \big\| \mathsf{pad} \Big]\cdots \Big]\Big]
$$

We now have two problems: This is shorter than the required length $N_\beta$ (the difference is of course $|A_1|+|\gamma_1|$ bytes), and furthermore we cannot just pad it with arbitrary bytes, because then the MAC $\gamma_1$ won't match when checked by the next node. 

So we have to construct the intermediate headers in such a way, that each node can reconstruct the last bytes of the next header exactly. Sphinx solves this by the following construction of "filler strings" $\phi_0,\dots, \phi_{\ell-1}$:

$$
\begin{align*}
\phi_0 &:= \emptyset \\
\phi_i &:= S_i\oplus \Big[\, \phi_{i-1} \;\|\;0^{|A_i|+|\gamma_i|} \,\Big] \\
S_i &:= \mathsf{STREAM}(e_{i-1})_{U_i\dots V_i-1} \\
U_i &:= N_\beta-|\phi_{i-1}| \\
V_i &:= N_\beta+|A_i|+|\gamma_i|
\end{align*}
$$

Here the funny thing in the definition of $\phi_i$ means basically the stream cipher $\mathsf{encdec}_{i-1}$ (with key $e_{i-1}!)$, except that it's _shifted_: The separator between $\phi_{i-1}$ and the zero bytes $0^{|A_i|+|\gamma_i|}$ should fall exactly at the $N_\beta$ position.

Only the last filler, $\phi_{\ell-1}$ is actually used to construct the header, but in fact $\phi_i$ are the last few bytes of the changing headers $\mathcal{H}_i$, as they are processed and forwarded by the mix nodes.

Now when the $i-1$-th node receives its $\beta_{i-1}$, then if before decryption with $\mathsf{encdec}_i$, they append $|A_i|+|\gamma_i|$ zero bytes, then after decryption and removing $A_i$ and $\gamma_i$ from the beginning, the result is exactly $\beta_i$, which they can use to construct the next hop's header.

### Illustration of the  process

Given a mix path $(A_0,A_1,A_2,A_3)$ consisting of 4 mix nodes, with a final destination $\Delta$, the $\beta$ part of the header looks like this for the four nodes (omitting the layered encryption for brevity):

    +------------+------------+------------+-------+-----+
    | Addr1 | M1 | Addr2 | M2 | Addr3 | M3 | Delta | pad |  <-- key0
    +------------+------------+------------+-------+-----+
    
    +------------+------------+-------+-----+------------+
    | Addr2 | M2 | Addr3 | M3 | Delta | pad |  filler1   |  <-- key1
    +------------+------------+-------+-----+------------+
    
    +------------+-------+-----+------------+------------+
    | Addr3 | M3 | Delta | pad |         filler2         |  <-- key2
    +------------+-------+-----+------------+------------+
    
    +-------+-----+------------+------------+------------+
    | Delta | pad |               filler3                |  <-- key3
    +-------+-----+------------+------------+------------+
    
