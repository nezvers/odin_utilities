#+build !js
package spacetimedb

import "core:fmt"
import "core:os"
import "core:testing"

@(test)
test_a_server_writes_its_log_to_a_file_and_listens_on_the_network :: proc(t: ^testing.T) {
    if !os.exists(ServerCliPath()) {
        fmt.println("[spacetimedb] no server: run `odin run spacetimedb/tool/setup`")
        return
    }
    root: string = "spacetimedb_test_server_lan"
    log: string = fmt.tprintf("%s/server.log", root)
    os.make_directory_all(root)
    defer os.remove_all(root)
    server: Server
    testing.expect(t, ServerStart(&server, {root = root, port = 3196, in_memory = true, log_file = log, lan = true}), "the server starts on every interface")
    testing.expect(t, ServerPing(server.endpoint), "and answers on the loopback")
    testing.expect_value(t, LanEndpoint(&server, "192.168.1.5"), Endpoint{host = "192.168.1.5", port = 3196})
    ServerStop(&server)
    text, error := os.read_entire_file(log, context.temp_allocator)
    testing.expect(t, error == nil && len(text) > 0, "the output of the server is in the log file")
}

// Needs the internet: `SPACETIMEDB_LIVE=1 odin test spacetimedb`. The public cloud answers /v1/ping over TLS: the handshake, the certificate check and HTTP over it.
@(test)
test_https_to_the_public_cloud :: proc(t: ^testing.T) {
    if os.get_env("SPACETIMEDB_LIVE", context.temp_allocator) != "1" { return }
    response: [1024]u8
    result: HttpResult = HttpRequest({host = "maincloud.spacetimedb.com", port = 443, secure = true}, .GET, "/v1/ping", nil, nil, response[:])
    testing.expectf(t, result.ok && result.status == 200, "ping over TLS: %v %d %s", result.ok, result.status, result.error)
    // and the websocket over TLS: a database that does not exist is refused with an HTTP answer, which proves the upgrade request went through the encrypted stream
    receive, message: [4096]u8
    socket: WebSocket
    protocols: [1]string = {PROTOCOL_V2}
    testing.expect(t, !WebSocketOpen(&socket, {host = "maincloud.spacetimedb.com", port = 443, secure = true}, "/v1/database/no-such-database-for-odin-test/subscribe", protocols[:], nil, receive[:], message[:]))
    testing.expect_value(t, socket.error, "the server refused the upgrade")
}
