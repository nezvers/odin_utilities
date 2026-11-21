package spacetimedb

// A SpacetimeDB server of your own that a program starts and stops: the standalone server of the release (`spacetimedb-cli start`, downloaded by setup.odin) in a process of its own, its files
// (data, keys, configuration) in a folder you name so that nothing of the user's own installation is touched, its output shown or thrown away. This is what makes a test session possible without
// anything installed by hand, and what a game does for a local or LAN session.
//
//     server: Server
//     if ServerStart(&server, {root = "run/server", port = 3101}) {          // waits until it answers
//         ...                                                                  // publish a module, connect clients
//         ServerStop(&server)
//     }

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

ServerOptions :: struct {
    cli: string,                // the spacetimedb-cli executable: "" is the one of setup.odin (`ServerCliPath`). The server cannot be started without the CLI: the CLI makes the keys that sign the identities (in `root`) and starts the standalone server as a child, which is why a stop kills the whole tree
    root: string,               // the folder for everything the server makes: data/, config, keys (made when it is missing)
    port: int,                  // on 127.0.0.1 (0: 3000)
    in_memory: bool,            // nothing is kept after the process ends (a test)
    show_output: bool,          // the output of the server goes to the output of this program (else it is thrown away unless `log_file` is set; the log of what a module writes is `DatabaseLogs`)
    log_file: string,           // the output of the server goes to this file (on Windows through a batch file with a redirection: a handle made by os.create is not inherited by a child there)
    lan: bool,                  // listen on every interface (0.0.0.0) so that other machines can connect to `LanEndpoint`; false: loopback only
    wait: time.Duration,        // how long to wait for it to answer (0: 30 seconds)
}

Server :: struct {
    process: os.Process,
    running: bool,
    endpoint: Endpoint,
    host: [16]u8,
    root: string,
    lan: bool,
}

SERVER_HOST :: "127.0.0.1"
SERVER_LAN_HOST :: "0.0.0.0"

// Starts the server and waits until `GET /v1/ping` is answered. False when the program is not there (run setup), the process cannot be made, or it does not answer in time (run it with `show_output` to see why).
ServerStart :: proc(server: ^Server, options: ServerOptions) -> bool {
    server^ = {}
    cli: string = options.cli if options.cli != "" else ServerCliPath()
    if !os.exists(cli) { return false }
    port: int = options.port if options.port > 0 else 3000
    os.make_directory_all(options.root)
    data: string = fmt.tprintf("%s/data", options.root)
    command: [dynamic]string
    command.allocator = context.temp_allocator
    listen_host: string = SERVER_LAN_HOST if options.lan else SERVER_HOST
    append(&command, cli, "--root-dir", options.root, "start", "--listen-addr", fmt.tprintf("%s:%d", listen_host, port), "--data-dir", data, "--non-interactive")
    if options.in_memory { append(&command, "--in-memory") }
    output: ^os.File = os.stdout if options.show_output else nil
    error_output: ^os.File = os.stderr if options.show_output else nil
    log: ^os.File
    defer if log != nil { os.close(log) }
    if options.log_file != "" {
        when ODIN_OS == .Windows {
            // a batch file runs the server with the redirection (the shell of cmd does the inheriting that os.create cannot)
            line: [dynamic]u8
            line.allocator = context.temp_allocator
            for part, i in command {
                if i > 0 { append(&line, ' ') }
                append(&line, '"')
                append(&line, ..transmute([]u8)part)
                append(&line, '"')
            }
            append(&line, ..transmute([]u8)fmt.tprintf(" > \"%s\" 2>&1\r\n", options.log_file))
            script: string = fmt.tprintf("%s/start_server.cmd", options.root)
            if os.write_entire_file(script, line[:]) != nil { return false }
            clear(&command)
            windows_script, _ := strings.replace_all(script, "/", "\\", context.temp_allocator)     // cmd reads a slash as a switch
            append(&command, "cmd", "/c", windows_script)
        } else {
            file, file_error := os.create(options.log_file)
            if file_error != nil { return false }
            log = file
            output, error_output = file, file
        }
    }
    process, start_error := os.process_start({command = command[:], stdout = output, stderr = error_output})
    if start_error != nil { return false }
    server.process, server.running, server.root, server.lan = process, true, options.root, options.lan
    server.endpoint = {host = SERVER_HOST, port = port}
    wait: time.Duration = options.wait if options.wait > 0 else 30 * time.Second
    start: time.Tick = time.tick_now()
    for time.tick_since(start) < wait {
        if ServerPing(server.endpoint) { return true }
        time.sleep(100 * time.Millisecond)
    }
    ServerStop(server)
    return false
}

// The address that other machines connect to when the server was started with `lan`: `local_address` is the address of this machine on the network (the caller knows it: an invitation, a
// discovery message of p2p), the port is the one of the server.
LanEndpoint :: proc(server: ^Server, local_address: string) -> Endpoint {
    return {host = local_address, port = server.endpoint.port}
}

// Stops it (the process is killed: the data of a server that keeps data is safe, the database commits as it goes)
ServerStop :: proc(server: ^Server) {
    if !server.running { return }
    // the CLI started the server as a child: the whole tree goes (taskkill /T on Windows, the children of the pid elsewhere)
    when ODIN_OS == .Windows {
        _, _, _, _ = os.process_exec({command = {"taskkill", "/F", "/T", "/PID", fmt.tprintf("%d", server.process.pid)}}, context.temp_allocator)
    } else {
        _, _, _, _ = os.process_exec({command = {"pkill", "-KILL", "-P", fmt.tprintf("%d", server.process.pid)}}, context.temp_allocator)
    }
    _ = os.process_kill(server.process)
    _, _ = os.process_wait(server.process)
    server.running = false
}

// Does a server answer at the endpoint (`GET /v1/ping`)
ServerPing :: proc(endpoint: Endpoint) -> bool {
    response: [512]u8
    result: HttpResult = HttpRequest(endpoint, .GET, "/v1/ping", nil, nil, response[:], 2 * time.Second)
    return result.ok && result.status == 200
}
