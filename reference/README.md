
Transport layer abstraction over Mix
------------------------------------

This is a WIP reference implementation of our proposed transport layer abstraction
over Mix, written in Haskell.

### Source code layout

- `Crypto` - cryptography primitives (symmetric crypto, X25519 key exchange, Lioness PRP)
- `Data` - data structures (octetstrings)
- `Mix` - modelling Mix itself
- `Simulate` - WIP Mix simulator
- `Sphinx` - Sphinx packet constructor
- `Transport` - transport layer

