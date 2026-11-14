# Web serve

A small static file server to try a web build (see `web_build`) in a browser. A browser refuses wasm from `file://`, so `bin/web` has to be served.

- GET and HEAD, content types by extension (`application/wasm` for wasm), a folder gets its `index.html`.
- `Cache-Control: no-store`, a rebuilt `main.wasm` is always fetched.
- Listens on the loopback address unless told otherwise. `..`, backslashes and NUL in a path are refused, so nothing outside of the folder is served.
- No hidden allocations: connections, request buffers and the file chunk are fixed arrays inside of `Server`.
- Connections are polled, a browser that opens a connection and sends nothing does not hold up the others.
- `cross_origin_isolated` adds COOP and COEP for SharedArrayBuffer (wasm threads).

```odin
server: web_serve.Server
web_serve.ServerInit(&server, {directory = "game/bin/web"})     // port 0 picks a free port, read Server.port
web_serve.ServerRun(&server)                                    // or call ServerPoll in a loop of your own
```

## Tool
```
odin run web_serve/tool -- web_build/demo_karl2d/game/bin/web --open
```
`--port N` (default 8000), `--open` opens the browser, `--isolated` sends COOP/COEP, `--any` listens on every interface so a phone on the same network can open the page.
Build and serve the web_build demo:
```
odin run web_build/demo_karl2d/build_web -- -o:size      (from web_build/)
odin run web_serve/tool -- web_build/demo_karl2d/game/bin/web --open
```

## Tests
`odin test web_serve -strict-style -vet`. The tests use real sockets on the loopback address with a free port: files and folders, a wasm larger than one chunk byte for byte,
404/403/405/400, HEAD, an idle connection next to a normal one, isolation headers.
