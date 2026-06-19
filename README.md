Transport over Mix
------------------

This is intended to become a specification and reference implementation of
a transport abstraction layer over the [Mix Protocol](https://lip.logos.co/ift-ts/raw/mix.html).

The idea is to hide the packet size and other limitations of Mix behind a nice
abstraction layer, so applications can pretend they are communicating over
a "normal" network not unlike TCP (a very slow, and moderately reliable, 
but otherwise pretty normally behaving network socket).

Furthermore, we also take the opportunity to document (including an executable
specification) both the Sphinx mix packet format, and SURBs (Single Use Reply Blocks).

### Quick Start

First (you normally only need to do this at most once):

```bash
cabal update      # update the package directory
```

Then:

```bash
cabal clean       # start from a clean state
cabal build       # build the library
cabal repl        # read-eval-print loop
```
