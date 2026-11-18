#+build !js
// The channel as tools for the agent: a small MCP server (Model Context Protocol, JSON-RPC 2.0 over stdin / stdout, one JSON object per
// line) that Claude Code starts as a child of the agent. It is the program itself in --mcp-bridge mode. It holds nothing: every tool call
// becomes one request to the running amsg through the control door (control.odin), which does the work and says what happened.
//
// Tools (the agent sees them as mcp__amsg__<name>):
//   say(text)           a message to everybody in the channel
//   tell(to, text)      a message to one member
//   send(to, path)      a file or a folder (only from the agent's own folder) to one member or "all"
//   run(to, command)    one shell command on the device of a member who gave remote control (remote.odin)
//   inbox()             what the channel said since the agent last looked
//   who()               the members, and which of them have an agent
// Why a server and not a shell command: a shell makes the agent's words a quoting problem and gives it a shell, a tool call is data and
// is all it can do.
package ai_messaging

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

MCP_LINE_MAX :: 64 * 1024

// What the bridge does with a tool call: `command` and `args` as the control door takes them. `text` is what goes back to the agent.
McpCall :: proc(user: rawptr, command: string, args: string) -> (text: string, ok: bool)

MCP_TOOLS :: `[` +
    `{"name":"say","description":"Send a message to everybody in the channel. Short and useful: the others read it, and their agents may answer.","inputSchema":{"type":"object","properties":{"text":{"type":"string","description":"The message (up to 800 characters)."}},"required":["text"]}},` +
    `{"name":"tell","description":"Send a private message to one member of the channel (a person or the person's agent).","inputSchema":{"type":"object","properties":{"to":{"type":"string","description":"The member's name, see who."},"text":{"type":"string","description":"The message (up to 800 characters)."}},"required":["to","text"]}},` +
    `{"name":"send","description":"Offer a file or a whole folder to one member, or to \"all\". Only files inside your own folder can be sent. The member decides whether to accept.","inputSchema":{"type":"object","properties":{"to":{"type":"string","description":"The member's name, or all."},"path":{"type":"string","description":"A file or folder inside your folder (a relative path is relative to it)."}},"required":["to","path"]}},` +
    `{"name":"run","description":"Run one shell command on the device of a member who gave you remote control. It runs there with that person's rights, one at a time, 60 s at most. The result arrives later as a message \"[run name] exit N: output\". Use it only for what your person asked.","inputSchema":{"type":"object","properties":{"to":{"type":"string","description":"The member's name, see who."},"command":{"type":"string","description":"One line (up to 400 characters)."}},"required":["to","command"]}},` +
    `{"name":"inbox","description":"Read what the channel has said since you last looked (messages, files offered, members coming and going). Empty when nothing is new.","inputSchema":{"type":"object","properties":{}}},` +
    `{"name":"who","description":"List the members of the channel and which of them have an agent.","inputSchema":{"type":"object","properties":{}}}` +
    `]`

// One line of the client (a JSON-RPC message) -> the line to answer with (temp allocator); `answered` false for a notification.
McpHandle :: proc(line: []byte, call: McpCall, user: rawptr) -> (response: string, answered: bool) {
    value, parse_error := json.parse(line, .JSON, false, context.temp_allocator)
    if parse_error != .None {
        return `{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"parse error"}}`, true
    }
    object, is_object := value.(json.Object)
    if !is_object {
        return `{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"invalid request"}}`, true
    }
    method, _ := object["method"].(json.String)
    id_value, has_id := object["id"]
    if !has_id {
        return "", false                               // a notification (notifications/initialized, ...): nothing to answer
    }
    id: string = "null"
    if encoded, marshal_error := json.marshal(id_value, {}, context.temp_allocator); marshal_error == nil {
        id = string(encoded)
    }
    params, _ := object["params"].(json.Object)
    switch method {
    case "initialize":
        version, _ := params["protocolVersion"].(json.String)
        if version == "" {
            version = "2024-11-05"
        }
        return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"result":{{"protocolVersion":%s,"capabilities":{{"tools":{{}}}},"serverInfo":{{"name":"amsg","version":"1"}}}}}}`, id, JsonQuote(version)), true
    case "ping":
        return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"result":{{}}}}`, id), true
    case "tools/list":
        return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"result":{{"tools":%s}}}}`, id, MCP_TOOLS), true
    case "tools/call":
        name, _ := params["name"].(json.String)
        arguments, _ := params["arguments"].(json.Object)
        command, args, valid := McpToolRequest(name, arguments)
        if !valid {
            return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"result":{{"content":[{{"type":"text","text":%s}}],"isError":true}}}}`, id, JsonQuote(fmt.tprintf("%s: the arguments are not right (see the tool description)", name))), true
        }
        text, ok := call(user, command, args)
        return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"result":{{"content":[{{"type":"text","text":%s}}],"isError":%v}}}}`, id, JsonQuote(text), !ok), true
    }
    return fmt.tprintf(`{{"jsonrpc":"2.0","id":%s,"error":{{"code":-32601,"message":"method not found"}}}}`, id), true
}

// A tool and its arguments as a control request. False: a name that is not a tool, or arguments of the wrong kind.
McpToolRequest :: proc(name: string, arguments: json.Object) -> (command: string, args: string, ok: bool) {
    text, has_text := arguments["text"].(json.String)
    to, has_to := arguments["to"].(json.String)
    path, has_path := arguments["path"].(json.String)
    run_command, has_run := arguments["command"].(json.String)
    switch name {
    case "run":
        return "run", strings.concatenate({to, "\n", run_command}, context.temp_allocator), has_to && has_run && to != "" && run_command != "" && !strings.contains_rune(to, '\n')
    case "say":
        return "say", text, has_text && text != ""
    case "tell":
        return "tell", strings.concatenate({to, "\n", text}, context.temp_allocator), has_to && has_text && to != "" && text != "" && !strings.contains_rune(to, '\n')
    case "send":
        return "send", strings.concatenate({to, "\n", path}, context.temp_allocator), has_to && has_path && to != "" && path != "" && !strings.contains_rune(to, '\n')
    case "inbox":
        return "inbox", "", true
    case "who":
        return "who", "", true
    }
    return
}

// The program in --mcp-bridge mode: reads requests from stdin until it closes, answers on stdout. The control door is in the environment
// (AMSG_CONTROL = 127.0.0.1:port, AMSG_TOKEN), put there by the amsg that started the agent.
McpServe :: proc() {
    address: string = os.get_env("AMSG_CONTROL", context.allocator)
    token: string = os.get_env("AMSG_TOKEN", context.allocator)
    Context :: struct {
        address, token: string,
    }
    bridge: Context = {address, token}
    call :: proc(user: rawptr, command: string, args: string) -> (text: string, ok: bool) {
        bridge: ^Context = cast(^Context)user
        response, call_ok := ControlCall(bridge.address, bridge.token, command, args, context.temp_allocator)
        if !call_ok {
            return "the channel program does not answer (is it still running?)", false
        }
        return response, !strings.has_prefix(response, "error:") && response != "denied"
    }
    pending: [dynamic]byte
    chunk: [4096]byte
    for {
        count, error := os.read(os.stdin, chunk[:])
        if error != nil || count <= 0 {
            return
        }
        for b in chunk[:count] {
            if b != '\n' {
                if len(pending) < MCP_LINE_MAX {
                    append(&pending, b)
                }
                continue
            }
            if len(strings.trim_space(string(pending[:]))) > 0 {
                response, answered := McpHandle(pending[:], call, &bridge)
                if answered {
                    out: string = fmt.tprintf("%s\n", response)
                    os.write(os.stdout, transmute([]byte)out)
                }
            }
            clear(&pending)
            free_all(context.temp_allocator)
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------- tests

McpTestCall :: proc(user: rawptr, command: string, args: string) -> (text: string, ok: bool) {
    log: ^[dynamic]string = cast(^[dynamic]string)user
    append(log, fmt.aprintf("%s|%s", command, args))
    return "sent" if command != "who" else "error: nobody", command != "who"
}

@(test)
McpTest :: proc(t: ^testing.T) {
    log: [dynamic]string
    defer {
        for entry in log {
            delete(entry)
        }
        delete(log)
    }
    ask :: proc(line: string, log: ^[dynamic]string) -> json.Object {
        response, answered := McpHandle(transmute([]byte)line, McpTestCall, log)
        if !answered {
            return nil
        }
        value, _ := json.parse(transmute([]byte)response, .JSON, false, context.temp_allocator)
        object, _ := value.(json.Object)
        return object
    }
    // initialize repeats the version the client asked for; a notification gets no answer
    initialize := ask(`{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude","version":"1"}}}`, &log)
    result, _ := initialize["result"].(json.Object)
    version, _ := result["protocolVersion"].(json.String)
    testing.expect_value(t, version, "2025-06-18")
    testing.expect(t, ask(`{"jsonrpc":"2.0","method":"notifications/initialized"}`, &log) == nil)

    // the list names the six tools, every one with a schema
    listing := ask(`{"jsonrpc":"2.0","id":"abc","method":"tools/list"}`, &log)
    id, _ := listing["id"].(json.String)
    testing.expect_value(t, id, "abc")
    list_result, _ := listing["result"].(json.Object)
    tools, _ := list_result["tools"].(json.Array)
    testing.expect_value(t, len(tools), 6)
    for tool in tools {
        entry, _ := tool.(json.Object)
        _, has_schema := entry["inputSchema"]
        testing.expect(t, has_schema)
    }

    // calls reach the program as control requests; the text of the answer goes back
    say := ask(`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"say","arguments":{"text":"hello \"group\"\nsecond line"}}}`, &log)
    say_result, _ := say["result"].(json.Object)
    content, _ := say_result["content"].(json.Array)
    first, _ := content[0].(json.Object)
    text, _ := first["text"].(json.String)
    testing.expect_value(t, text, "sent")
    is_error, _ := say_result["isError"].(json.Boolean)
    testing.expect(t, !is_error)
    ask(`{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"tell","arguments":{"to":"bob","text":"psst"}}}`, &log)
    ask(`{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"send","arguments":{"to":"all","path":"notes.txt"}}}`, &log)
    ask(`{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"inbox","arguments":{}}}`, &log)
    testing.expect_value(t, len(log), 4)
    if len(log) == 4 {
        testing.expect_value(t, log[0], "say|hello \"group\"\nsecond line")
        testing.expect_value(t, log[1], "tell|bob\npsst")
        testing.expect_value(t, log[2], "send|all\nnotes.txt")
        testing.expect_value(t, log[3], "inbox|")
    }

    // an error of the program is an error result (the agent sees it and can say so), wrong arguments never reach it
    who := ask(`{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"who","arguments":{}}}`, &log)
    who_result, _ := who["result"].(json.Object)
    who_error, _ := who_result["isError"].(json.Boolean)
    testing.expect(t, who_error)
    before: int = len(log)
    bad := ask(`{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"say","arguments":{}}}`, &log)
    bad_result, _ := bad["result"].(json.Object)
    bad_flag, _ := bad_result["isError"].(json.Boolean)
    testing.expect(t, bad_flag)
    ask(`{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"delete_everything","arguments":{}}}`, &log)
    testing.expect_value(t, len(log), before)                           // the two bad calls were not passed on

    // garbage and unknown methods are answered with errors, not with a crash
    garbage := ask(`{{{`, &log)
    testing.expect(t, garbage["error"] != nil)
    unknown := ask(`{"jsonrpc":"2.0","id":10,"method":"resources/list"}`, &log)
    unknown_error, _ := unknown["error"].(json.Object)
    code, _ := unknown_error["code"].(json.Float)
    testing.expect_value(t, int(code), -32601)
}
