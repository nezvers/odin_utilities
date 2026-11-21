# web_serve: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `web_serve.odin` (`Server*` procs: static GET/HEAD file server over `core:net`, fixed buffers, polled connections, `ResolvePath` refuses traversal; tests at the bottom use real loopback sockets), `tool/` (`odin run web_serve/tool -- <dir> --open`). No raylib/karl2d demo: nothing is drawn, the tool serves the web_build demo.
