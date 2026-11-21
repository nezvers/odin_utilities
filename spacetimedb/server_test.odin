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
    testing.expect_value(t, LanEndpoint(&server, "192.168.1.5"), Endpoint{"192.168.1.5", 3196})
    ServerStop(&server)
    text, error := os.read_entire_file(log, context.temp_allocator)
    testing.expect(t, error == nil && len(text) > 0, "the output of the server is in the log file")
}
