// The download helper executable for native messaging (Chrome, Edge, Opera, Firefox all speak the same stdio protocol):
// every packet is a 4 byte length (little endian, the byte order of the machine) and that many bytes of JSON. The browser starts one helper per
// message and closes it after the reply. All decisions are in the `native` package.
//
// As a job: `shorts_helper_host --job download <id> [youtube-dl command]` / `--job install`, started by the helper itself.
package main

import "core:os"
import native "../native"

MAX_PACKET :: 1024 * 1024

main :: proc() {
	config: native.Config
	arguments: []string = os.args[1:]
	if len(arguments) >= 3 && arguments[0] == "--job" {
		if len(arguments) >= 4 {
			config.ytdl_command = arguments[3]
		}
		switch arguments[1] {
		case "download": os.exit(native.NativeRunDownload(config, arguments[2]))
		case "install": os.exit(native.NativeRunInstall(config))
		}
		os.exit(2)
	}

	// the browser passes the origin of the extension as an argument, not needed
	for {
		header: [4]u8
		if n, error := os.read_full(os.stdin, header[:]); error != nil || n != 4 {
			return
		}
		length: int = int(header[0]) | int(header[1]) << 8 | int(header[2]) << 16 | int(header[3]) << 24
		if length <= 0 || length > MAX_PACKET {
			return
		}
		body: []u8 = make([]u8, length, context.temp_allocator)
		if n, error := os.read_full(os.stdin, body); error != nil || n != length {
			return
		}

		request, ok := native.NativeParseRequest(body)
		reply: string = native.NativeHandle(config, request) if ok else "unknown"
		data: []u8 = native.NativeEncodeReply(reply)
		out_header: [4]u8 = {u8(len(data)), u8(len(data) >> 8), u8(len(data) >> 16), u8(len(data) >> 24)}
		os.write(os.stdout, out_header[:])
		os.write(os.stdout, data)
		free_all(context.temp_allocator)
	}
}
