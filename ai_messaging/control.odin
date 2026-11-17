#+build !js
// The door between a running amsg and the programs that act for its agent: a TCP port on the loopback address of this computer, and a token.
// The agent's MCP server (mcp.odin, started by Claude Code as a child of the agent) connects here to say something in the channel, send a
// file or read what came in. Nobody else is supposed to: the port is only reachable from this computer and every request starts with the
// token, which exists only in the environment of that MCP server (and in its config file in the private folder of this agent).
//
// A request is "<token>\n<command>\n<arguments>" and then the sender closes its writing end; the answer is plain text up to the end of the
// connection. One request per connection, read with a short time limit, so a stuck client cannot hold the program up.
package ai_messaging

import "base:runtime"
import "core:crypto"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

CONTROL_REQUEST_MAX :: 4096
CONTROL_ANSWER_MAX :: 64 * 1024
CONTROL_READ_MS :: 500

ControlServer :: struct {
    listener: net.TCP_Socket,
    open: bool,
    port: int,
    token: [32]byte,                     // 32 hex digits
}

ControlRequest :: struct {
    socket: net.TCP_Socket,
    data: [CONTROL_REQUEST_MAX]byte,
    length: int,
    command: string,                     // views into `data`
    args: string,
}

ControlOpen :: proc(server: ^ControlServer) -> bool {
    server^ = {}
    listener, error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    if error != nil {
        return false
    }
    endpoint, endpoint_error := net.bound_endpoint(listener)
    if endpoint_error != nil {
        net.close(listener)
        return false
    }
    net.set_blocking(listener, false)
    random: [16]byte
    crypto.rand_bytes(random[:])
    digits: string = "0123456789abcdef"
    for b, i in random {
        server.token[2 * i] = digits[b >> 4]
        server.token[2 * i + 1] = digits[b & 15]
    }
    server.listener = listener
    server.port = endpoint.port
    server.open = true
    return true
}

ControlToken :: proc(server: ^ControlServer) -> string {
    return string(server.token[:])
}

ControlClose :: proc(server: ^ControlServer) {
    if server.open {
        net.close(server.listener)
        server.open = false
    }
}

// The next valid request, if one is waiting. A connection with a wrong token or a request that does not make sense is answered and closed
// here. The caller answers the valid one with ControlReply (which closes it).
ControlPoll :: proc(server: ^ControlServer, request: ^ControlRequest) -> bool {
    if !server.open {
        return false
    }
    client, _, accept_error := net.accept_tcp(server.listener)
    if accept_error != nil {
        return false
    }
    net.set_blocking(client, true)
    net.set_option(client, .Receive_Timeout, time.Millisecond * CONTROL_READ_MS)
    net.set_option(client, .Send_Timeout, time.Millisecond * CONTROL_READ_MS)
    request.socket = client
    request.length = 0
    for request.length < len(request.data) {
        count, error := net.recv_tcp(client, request.data[request.length:])
        if error != nil || count <= 0 {
            break
        }
        request.length += count
    }
    text: string = string(request.data[:request.length])
    first: int = strings.index_byte(text, '\n')
    if first < 0 || text[:first] != string(server.token[:]) {
        net.send_tcp(client, transmute([]byte)string("denied"))
        net.close(client)
        return false
    }
    rest: string = text[first + 1:]
    second: int = strings.index_byte(rest, '\n')
    request.command = rest if second < 0 else rest[:second]
    request.args = "" if second < 0 else rest[second + 1:]
    return true
}

ControlReply :: proc(request: ^ControlRequest, text: string) {
    net.send_tcp(request.socket, transmute([]byte)text)
    net.close(request.socket)
}

// The other side: one request to the server at "127.0.0.1:port". `response` is allocated.
ControlCall :: proc(address: string, token: string, command: string, args: string, allocator := context.allocator) -> (response: string, ok: bool) {
    colon: int = strings.last_index_byte(address, ':')
    if colon < 0 {
        return
    }
    port, port_ok := strconv.parse_int(address[colon + 1:])
    if !port_ok || address[:colon] != "127.0.0.1" || len(token) != 32 {
        return                                   // only this computer
    }
    socket, error := net.dial_tcp_from_endpoint({address = net.IP4_Loopback, port = port})
    if error != nil {
        return
    }
    defer net.close(socket)
    net.set_option(socket, .Receive_Timeout, time.Second * 10)
    net.set_option(socket, .Send_Timeout, time.Second * 5)
    request: string = strings.concatenate({token, "\n", command, "\n", args}, context.temp_allocator)
    if len(request) > CONTROL_REQUEST_MAX {
        return "the request is too long", false
    }
    if _, send_error := net.send_tcp(socket, transmute([]byte)request); send_error != nil {
        return
    }
    net.shutdown(socket, .Send)
    answer: [dynamic]byte
    defer delete(answer)
    chunk: [4096]byte
    for len(answer) < CONTROL_ANSWER_MAX {
        count, receive_error := net.recv_tcp(socket, chunk[:])
        if receive_error != nil || count <= 0 {
            break
        }
        append(&answer, ..chunk[:count])
    }
    return strings.clone(string(answer[:]), allocator), len(answer) > 0
}

// ---------------------------------------------------------------------------------------------------------------- tests

ControlJob :: struct {
    address, token, command, args: string,
    response: string,
    ok: bool,
    done: bool,
}

ControlJobRun :: proc(data: rawptr) {
    job: ^ControlJob = cast(^ControlJob)data
    job.response, job.ok = ControlCall(job.address, job.token, job.command, job.args)
    sync.atomic_store(&job.done, true)
}

// The client runs on a thread while this one polls the server, as the main loop of the program does.
ControlExchange :: proc(server: ^ControlServer, token: string, command: string, args: string, seen: ^[dynamic]string) -> (response: string, ok: bool) {
    job: ControlJob = {address = fmt.tprintf("127.0.0.1:%d", server.port), token = token, command = command, args = args}
    worker: ^thread.Thread = thread.create_and_start_with_data(&job, ControlJobRun)
    for _ in 0 ..< 3000 {
        request: ControlRequest
        if ControlPoll(server, &request) {
            append(seen, strings.clone(request.command))
            append(seen, strings.clone(request.args))
            ControlReply(&request, "answer to the request")
        }
        if sync.atomic_load(&job.done) {
            break
        }
        time.sleep(time.Millisecond)
    }
    thread.join(worker)
    thread.destroy(worker)
    // the thread allocated the answer with its own (heap) allocator: a copy for the allocator of the test
    response = strings.clone(job.response)
    delete(job.response, runtime.heap_allocator())
    return response, job.ok
}

@(test)
ControlTest :: proc(t: ^testing.T) {
    server: ControlServer
    testing.expect(t, ControlOpen(&server))
    defer ControlClose(&server)
    testing.expect_value(t, len(ControlToken(&server)), 32)
    seen: [dynamic]string
    defer {
        for text in seen {
            delete(text)
        }
        delete(seen)
    }

    // the right token reaches the program and gets its answer; the arguments keep their newlines
    response, ok := ControlExchange(&server, ControlToken(&server), "tell", "bob\nline one\nline two", &seen)
    testing.expect(t, ok)
    testing.expect_value(t, response, "answer to the request")
    testing.expect_value(t, len(seen), 2)
    if len(seen) == 2 {
        testing.expect_value(t, seen[0], "tell")
        testing.expect_value(t, seen[1], "bob\nline one\nline two")
    }
    delete(response)

    // a wrong token is denied and never reaches the program
    for text in seen {
        delete(text)
    }
    clear(&seen)
    response, ok = ControlExchange(&server, "00000000000000000000000000000000", "say", "hello", &seen)
    testing.expect_value(t, response, "denied")
    testing.expect_value(t, len(seen), 0)
    delete(response)

    // only this computer
    _, remote_ok := ControlCall("192.0.2.1:9999", ControlToken(&server), "say", "x")
    testing.expect(t, !remote_ok)
}
