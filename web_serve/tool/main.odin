// Serve a web build to try it in a browser:
//   odin run web_serve/tool -- web_build/demo_karl2d/game/bin/web --open
//
//   <directory>     the folder to serve, for a web_build it is <source>/bin/web
//   --port N        default 8000, 0 picks a free one
//   --open          open the page in the default browser
//   --isolated      send COOP and COEP headers (SharedArrayBuffer, wasm threads)
//   --any           listen on every interface, so a phone on the same network can open it
package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import web_serve ".."

main :: proc() {
	config: web_serve.ServerConfig = {port = 8000, log = true}
	open_browser: bool

	arguments: []string = os.args[1:]
	for i := 0; i < len(arguments); i += 1 {
		switch arguments[i] {
		case "--port":
			i += 1
			if i >= len(arguments) { usage(); return }
			port, ok := strconv.parse_int(arguments[i])
			if !ok { usage(); return }
			config.port = port
		case "--open":
			open_browser = true
		case "--isolated":
			config.cross_origin_isolated = true
		case "--any":
			config.address = net.IP4_Any
		case:
			config.directory = arguments[i]
		}
	}
	if len(config.directory) == 0 || !os.is_dir(config.directory) {
		usage()
		return
	}

	server: web_serve.Server
	if !web_serve.ServerInit(&server, config) {
		fmt.eprintfln("Could not listen on port %d, is something else using it?", config.port)
		os.exit(1)
	}
	defer web_serve.ServerShutdown(&server)

	buffer: [64]u8
	url: string = web_serve.ServerUrl(&server, buffer[:])
	fmt.printfln("Serving %s at %s (Ctrl+C to stop)", config.directory, url)
	if open_browser {
		web_serve.ServerOpenBrowser(url)
	}
	web_serve.ServerRun(&server)
}

usage :: proc() {
	fmt.eprintln("Usage: odin run web_serve/tool -- <directory> [--port N] [--open] [--isolated] [--any]")
	os.exit(1)
}
