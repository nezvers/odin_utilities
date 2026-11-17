// A stand-in for `claude -p --input-format stream-json --output-format stream-json`, for the tests of ai_messaging: no network, no model, no cost.
// It takes the same command line as agent.odin gives to Claude Code and answers in the same JSON lines.
//
//   init line first: {"type":"system","subtype":"init","model":<--model, or "fake-default">}
//   for every user message: an assistant text "echo: <content>" and a result line; when the text after "] " starts with a command it also acts
//   on the channel the way the agent's MCP server would (the control door named in the --mcp-config file):
//     say:<text>   tell:<name>:<text>   send:<name>:<path>   inbox   who   prompt (prints the system prompt file)   die (exits)
//     then it prints the answer of the door as a second assistant text
// The end of its input ends it.
package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import ai "../.."

main :: proc() {
    model: string = "fake-default"
    config_path, prompt_path: string
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--model":
            i += 1
            model = os.args[i] if i < len(os.args) else model
        case "--mcp-config":
            i += 1
            config_path = os.args[i] if i < len(os.args) else ""
        case "--append-system-prompt-file":
            i += 1
            prompt_path = os.args[i] if i < len(os.args) else ""
        }
    }
    address, token: string
    if data, error := os.read_entire_file(config_path, context.allocator); error == nil {
        if value, parse_error := json.parse(data, .JSON, false, context.allocator); parse_error == .None {
            root, _ := value.(json.Object)
            servers, _ := root["mcpServers"].(json.Object)
            amsg, _ := servers["amsg"].(json.Object)
            env, _ := amsg["env"].(json.Object)
            address, _ = env["AMSG_CONTROL"].(json.String)
            token, _ = env["AMSG_TOKEN"].(json.String)
        }
    }
    Print(fmt.tprintf(`{{"type":"system","subtype":"init","model":%s}}`, ai.JsonQuote(model)))

    pending: [dynamic]byte
    chunk: [4096]byte
    for {
        count, error := os.read(os.stdin, chunk[:])
        if error != nil || count <= 0 {
            return
        }
        for b in chunk[:count] {
            if b != '\n' {
                append(&pending, b)
                continue
            }
            Handle(string(pending[:]), address, token, prompt_path)
            clear(&pending)
        }
    }
}

Print :: proc(line: string) {
    out: string = fmt.tprintf("%s\n", line)
    os.write(os.stdout, transmute([]byte)out)
}

Say :: proc(text: string) {
    Print(fmt.tprintf(`{{"type":"assistant","message":{{"content":[{{"type":"text","text":%s}}]}}}}`, ai.JsonQuote(text)))
}

Handle :: proc(line: string, address: string, token: string, prompt_path: string) {
    value, parse_error := json.parse(transmute([]byte)line, .JSON, false, context.temp_allocator)
    if parse_error != .None {
        return
    }
    root, _ := value.(json.Object)
    message, _ := root["message"].(json.Object)
    content, _ := message["content"].(json.String)
    Print(`{"type":"system","subtype":"init","model":"again"}`)             // Claude Code repeats its init line with every turn
    Say(fmt.tprintf("echo: %s", content))
    command: string = content
    if close := strings.index(content, "] "); close >= 0 {
        command = content[close + 2:]
    }
    switch {
    case strings.has_prefix(command, "say:"):
        Door(address, token, "say", command[4:])
    case strings.has_prefix(command, "tell:"):
        parts: []string = strings.split_n(command[5:], ":", 2, context.temp_allocator)
        if len(parts) == 2 {
            Door(address, token, "tell", fmt.tprintf("%s\n%s", parts[0], parts[1]))
        }
    case strings.has_prefix(command, "send:"):
        parts: []string = strings.split_n(command[5:], ":", 2, context.temp_allocator)
        if len(parts) == 2 {
            Door(address, token, "send", fmt.tprintf("%s\n%s", parts[0], parts[1]))
        }
    case command == "inbox":
        Door(address, token, "inbox", "")
    case command == "who":
        Door(address, token, "who", "")
    case command == "prompt":
        if text, error := os.read_entire_file(prompt_path, context.temp_allocator); error == nil {
            Say(string(text))
        }
    case command == "die":
        os.exit(3)
    }
    Print(`{"type":"result","subtype":"success","is_error":false,"result":"","total_cost_usd":0.001}`)
}

Door :: proc(address: string, token: string, command: string, args: string) {
    response, ok := ai.ControlCall(address, token, command, args, context.temp_allocator)
    Say(fmt.tprintf("door %s: %s", command, response if ok else "no answer"))
}
