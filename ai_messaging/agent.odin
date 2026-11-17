#+build !js
// The AI agent of a member: a `claude -p` process (Claude Code, non interactive) that is kept open and talked to in stream-json. Lines go in
// as user messages ({"type":"user","message":{...}}), what Claude does comes out as one JSON object per line: this file turns the lines that
// matter (its answers, the tools it calls, the end of a turn, its exit) into AgentEvents for the program.
//
// What the agent is allowed to do is decided here, not by Claude's settings: it starts with NO built in tools (`--tools=`), none of the
// settings, hooks, plugins or MCP servers of the person (`--setting-sources=`, `--strict-mcp-config`), and one MCP server of ours, `amsg`
// (the program itself in --mcp-bridge mode, see mcp.odin), whose tools are say / tell / send / inbox / who. Everything the agent reads from
// other members is text from strangers: with no shell and no file tools the worst a hostile message can do is make it say something.
// `tools` widens that on purpose (for example "Read,Glob" to let it read what was received).
//
// One reader thread per agent (a blocked read must not stop the network) parses the lines and queues the events; AgentPoll is for the
// main loop. Windows note: Odin drops an empty argument from a command line, so options that need an empty value are written as `--x=`.
package ai_messaging

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

AGENT_EVENTS :: 64
AGENT_TEXT_MAX :: 1800                   // one event carries at most this much text; a longer answer comes as several events
AGENT_LINE_MAX :: 1 << 20                // a longer line of output is skipped (the init line with a big skill list is about 5 KB)

AgentState :: enum {
    NONE,
    RUNNING,
    ENDED,
}

AgentEventKind :: enum {
    NONE,
    READY,                               // the session started: text = the model that answers
    TEXT,                                // the agent says something (to the person at the keyboard)
    TOOL,                                // the agent calls a tool: text = name and arguments, short
    TOOL_ERROR,                          // a tool call was refused or failed: text says why
    DONE,                                // the turn is over; `cost` is its price in US dollars; is_error + text when it went wrong
    ENDED,                               // the process is gone (text says how)
}

AgentEvent :: struct {
    kind: AgentEventKind,
    is_error: bool,
    cost: f64,
    text: [AGENT_TEXT_MAX]byte,
    text_length: int,
}

AgentEventText :: proc(event: ^AgentEvent) -> string {
    return string(event.text[:event.text_length])
}

AgentConfig :: struct {
    command: string,                     // "claude" (looked up in PATH) or a full path
    model: string,                       // "haiku", "sonnet", "opus" or a full model id; "" = what Claude Code uses by default
    tools: string,                       // built in tools to allow besides the amsg ones, "Read,Glob" ("" = none)
    working_dir: string,                 // where the agent runs (it has no tool that uses it unless `tools` adds some)
    mcp_config: string,                  // file with the MCP server that gives it the channel (made by the session)
    prompt_file: string,                 // file with the text appended to the system prompt: who it is, what the channel is
    log_file: string,                    // stderr of Claude Code goes here ("" = nowhere)
}

Agent :: struct {
    state: AgentState,
    process: os.Process,
    input: ^os.File,
    output: ^os.File,
    log: ^os.File,
    reader: ^thread.Thread,
    mutex: sync.Mutex,
    events: [AGENT_EVENTS]AgentEvent,
    head: int,
    count: int,
    model: [AGENT_MODEL_MAX]byte,        // as asked for
    model_length: int,
    sent: int,                           // messages given to it
    done: int,                           // turns it finished
}

// A model name is a word of letters, digits and . _ : - [ ] only: it goes to a command line and comes from other people's requests too.
AgentModelValid :: proc(model: string) -> bool {
    if len(model) > AGENT_MODEL_MAX {
        return false
    }
    for c in transmute([]byte)model {
        ok: bool = c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '.' || c == '_' || c == ':' || c == '-' || c == '[' || c == ']'
        if !ok {
            return false
        }
    }
    return true
}

AgentModel :: proc(agent: ^Agent) -> string {
    return string(agent.model[:agent.model_length])
}

AgentRunning :: proc(agent: ^Agent) -> bool {
    return agent.state == .RUNNING
}

// Turns still being worked on (what was sent and has no answer yet).
AgentBusy :: proc(agent: ^Agent) -> bool {
    return agent.state == .RUNNING && agent.sent > agent.done
}

// The command line of the agent: everything is decided here.
AgentCommand :: proc(config: AgentConfig, allocator := context.temp_allocator) -> []string {
    command: [dynamic]string
    command.allocator = allocator
    append(&command, config.command if config.command != "" else "claude")
    append(&command, "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--no-session-persistence")
    append(&command, "--setting-sources=", "--strict-mcp-config", "--mcp-config", config.mcp_config)
    append(&command, fmt.aprintf("--tools=%s", config.tools, allocator = allocator))
    allowed: string = "mcp__amsg" if config.tools == "" else fmt.aprintf("mcp__amsg,%s", config.tools, allocator = allocator)
    append(&command, "--allowedTools", allowed)
    if config.prompt_file != "" {
        append(&command, "--append-system-prompt-file", config.prompt_file)
    }
    if config.model != "" {
        append(&command, "--model", config.model)
    }
    return command[:]
}

// Starts the process. `error` says what is wrong (no Claude Code, a bad model name, ...).
AgentStart :: proc(agent: ^Agent, config: AgentConfig) -> (error: string, ok: bool) {
    if agent.state == .RUNNING {
        return "the agent is already running", false
    }
    if !AgentModelValid(config.model) {
        return "the model name has characters that a model name does not have", false
    }
    agent^ = {}
    agent.model_length = copy(agent.model[:], config.model)
    stdin_read, stdin_write, stdin_error := os.pipe()
    stdout_read, stdout_write, stdout_error := os.pipe()
    if stdin_error != nil || stdout_error != nil {
        return "cannot make the pipes for the agent", false
    }
    if config.log_file != "" {
        agent.log, _ = os.open(config.log_file, {.Write, .Create, .Trunc})
    }
    // the environment of the agent is ours plus a mark: a program run in it (amsg, if the agent were given a shell) knows it is not a person
    environment, _ := os.environ(context.temp_allocator)
    marked: [dynamic]string
    marked.allocator = context.temp_allocator
    append(&marked, ..environment)
    append(&marked, "AMSG_AGENT=1")
    process, start_error := os.process_start({
        working_dir = config.working_dir,
        env = marked[:],
        command = AgentCommand(config),
        stdin = stdin_read,
        stdout = stdout_write,
        stderr = agent.log,
    })
    // our copies of the ends that belong to the child go: the reader sees the end of the output when the child is gone
    os.close(stdin_read)
    os.close(stdout_write)
    if start_error != nil {
        os.close(stdin_write)
        os.close(stdout_read)
        if agent.log != nil {
            os.close(agent.log)
        }
        return fmt.tprintf("cannot start \"%s\" (%v): is Claude Code installed and in the PATH? --agent-cmd gives its path", config.command if config.command != "" else "claude", start_error), false
    }
    agent.process = process
    agent.input = stdin_write
    agent.output = stdout_read
    agent.state = .RUNNING
    agent.reader = thread.create_and_start_with_data(agent, AgentRead)
    return "", true
}

// A user message for the agent.
AgentSend :: proc(agent: ^Agent, text: string) -> bool {
    if agent.state != .RUNNING {
        return false
    }
    line: string = fmt.tprintf(`{{"type":"user","message":{{"role":"user","content":%s}}}}%s`, JsonQuote(text), "\n")
    if _, error := os.write(agent.input, transmute([]byte)line); error != nil {
        return false
    }
    agent.sent += 1
    return true
}

// Ends the agent: closes its input (Claude Code ends at that), a moment later the process is killed if it is still there.
AgentStop :: proc(agent: ^Agent) {
    if agent.state == .NONE {
        return
    }
    if agent.input != nil {
        os.close(agent.input)
        agent.input = nil
    }
    if agent.state == .RUNNING || agent.state == .ENDED {
        // process_wait gives the handle back itself when the process has ended
        state, wait_error := os.process_wait(agent.process, 1500 * time.Millisecond)
        if wait_error != nil || !state.exited {
            _ = os.process_kill(agent.process)
            _, _ = os.process_wait(agent.process, 3000 * time.Millisecond)
        }
    }
    if agent.reader != nil {
        thread.join(agent.reader)
        thread.destroy(agent.reader)
        agent.reader = nil
    }
    if agent.output != nil {
        os.close(agent.output)
        agent.output = nil
    }
    if agent.log != nil {
        os.close(agent.log)
        agent.log = nil
    }
    agent.state = .NONE
    agent.count = 0
}

AgentPoll :: proc(agent: ^Agent) -> (event: AgentEvent, ok: bool) {
    sync.mutex_lock(&agent.mutex)
    defer sync.mutex_unlock(&agent.mutex)
    if agent.count == 0 {
        return
    }
    event = agent.events[agent.head]
    agent.head = (agent.head + 1) % AGENT_EVENTS
    agent.count -= 1
    if event.kind == .DONE {
        agent.done += 1
    }
    return event, true
}

@(private)
AgentPush :: proc(agent: ^Agent, kind: AgentEventKind, text: string, is_error: bool = false, cost: f64 = 0) {
    for {
        sync.mutex_lock(&agent.mutex)
        if agent.count < AGENT_EVENTS {
            event: ^AgentEvent = &agent.events[(agent.head + agent.count) % AGENT_EVENTS]
            event^ = {kind = kind, is_error = is_error, cost = cost}
            event.text_length = min(len(text), AGENT_TEXT_MAX)
            copy(event.text[:event.text_length], text)
            agent.count += 1
            sync.mutex_unlock(&agent.mutex)
            return
        }
        sync.mutex_unlock(&agent.mutex)
        time.sleep(time.Millisecond)
    }
}

// Long text in pieces that fit an event, cut at a line end or a space when there is one.
@(private)
AgentPushText :: proc(agent: ^Agent, kind: AgentEventKind, text: string) {
    rest: string = strings.trim_space(text)
    for len(rest) > 0 {
        piece: int = min(len(rest), AGENT_TEXT_MAX)
        if piece < len(rest) {
            if cut := strings.last_index_any(rest[:piece], "\n "); cut > piece / 2 {
                piece = cut
            }
            // never in the middle of a UTF-8 sequence
            for piece > 0 && piece < len(rest) && rest[piece] & 0xC0 == 0x80 {
                piece -= 1
            }
        }
        AgentPush(agent, kind, strings.trim_space(rest[:piece]))
        rest = strings.trim_space(rest[piece:])
    }
}

// One line of the output of Claude Code. Views into the parsed value are only used before it is deleted.
AgentLine :: proc(agent: ^Agent, line: []byte) {
    value, parse_error := json.parse(line, .JSON, false, context.temp_allocator)
    if parse_error != .None {
        return
    }
    object, is_object := value.(json.Object)
    if !is_object {
        return
    }
    kind, _ := object["type"].(json.String)
    switch kind {
    case "system":
        subtype, _ := object["subtype"].(json.String)
        if subtype == "init" {
            model, _ := object["model"].(json.String)
            AgentPush(agent, .READY, model)
        }
    case "assistant":
        message, _ := object["message"].(json.Object)
        blocks, _ := message["content"].(json.Array)
        for block in blocks {
            part, _ := block.(json.Object)
            block_kind, _ := part["type"].(json.String)
            switch block_kind {
            case "text":
                text, _ := part["text"].(json.String)
                AgentPushText(agent, .TEXT, text)
            case "tool_use":
                name, _ := part["name"].(json.String)
                input_text: string
                if input, has_input := part["input"]; has_input {
                    if encoded, marshal_error := json.marshal(input, {}, context.temp_allocator); marshal_error == nil {
                        input_text = string(encoded)
                    }
                }
                AgentPush(agent, .TOOL, fmt.tprintf("%s %s", name, input_text[:min(len(input_text), 300)]))
            }
        }
    case "user":
        // a tool result that is an error: usually a call that the permissions refused
        message, _ := object["message"].(json.Object)
        blocks, _ := message["content"].(json.Array)
        for block in blocks {
            part, _ := block.(json.Object)
            block_kind, _ := part["type"].(json.String)
            is_error, _ := part["is_error"].(json.Boolean)
            if block_kind == "tool_result" && is_error {
                text, _ := part["content"].(json.String)
                AgentPush(agent, .TOOL_ERROR, text)
            }
        }
    case "result":
        failed, _ := object["is_error"].(json.Boolean)
        cost, _ := object["total_cost_usd"].(json.Float)
        result: string
        if failed {
            result, _ = object["result"].(json.String)
        }
        AgentPush(agent, .DONE, result, failed, cost)
    }
}

@(private)
AgentRead :: proc(data: rawptr) {
    agent: ^Agent = cast(^Agent)data
    chunk: [4096]byte
    line: [dynamic]byte
    defer delete(line)
    skipping: bool
    for {
        read, error := os.read(agent.output, chunk[:])
        if error != nil || read <= 0 {
            break
        }
        for b in chunk[:read] {
            if b == '\n' {
                if !skipping && len(line) > 0 {
                    AgentLine(agent, line[:])
                    free_all(context.temp_allocator)
                }
                clear(&line)
                skipping = false
            } else if !skipping {
                if len(line) >= AGENT_LINE_MAX {
                    skipping = true
                    clear(&line)
                } else {
                    append(&line, b)
                }
            }
        }
    }
    AgentPush(agent, .ENDED, "the agent process ended")
    agent.state = .ENDED
}

// ---------------------------------------------------------------------------------------------------------------- JSON text

// A string as a JSON string literal (temp allocator).
JsonQuote :: proc(text: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    strings.write_byte(&builder, '"')
    for i in 0 ..< len(text) {
        c: u8 = text[i]
        switch c {
        case '"':
            strings.write_string(&builder, `\"`)
        case '\\':
            strings.write_string(&builder, `\\`)
        case '\n':
            strings.write_string(&builder, `\n`)
        case '\r':
            strings.write_string(&builder, `\r`)
        case '\t':
            strings.write_string(&builder, `\t`)
        case:
            if c < 32 {
                fmt.sbprintf(&builder, `\u%04x`, int(c))
            } else {
                strings.write_byte(&builder, c)
            }
        }
    }
    strings.write_byte(&builder, '"')
    return strings.to_string(builder)
}

// ---------------------------------------------------------------------------------------------------------------- tests

@(test)
AgentModelTest :: proc(t: ^testing.T) {
    for good in ([?]string{"", "haiku", "sonnet", "opus", "claude-haiku-5-5", "claude-opus-5-5[1m]", "claude-sonnet-4-20250514"}) {
        testing.expectf(t, AgentModelValid(good), "%q", good)
    }
    for bad in ([?]string{"a b", "haiku;rm", "x\"y", "--model", "a\nb", "$(x)", "name/with/slash"}) {
        // "--model" is made of allowed characters: a model name that looks like an option is harmless as an argument of --model, but refuse it
        // anyway when it starts with a dash
        valid: bool = AgentModelValid(bad) && !strings.has_prefix(bad, "-")
        testing.expectf(t, !valid, "%q", bad)
    }
    testing.expect(t, !AgentModelValid(strings.repeat("a", AGENT_MODEL_MAX + 1, context.temp_allocator)))
}

@(test)
AgentCommandTest :: proc(t: ^testing.T) {
    plain: []string = AgentCommand({command = "claude", model = "haiku", mcp_config = "c.json", prompt_file = "p.txt"})
    joined: string = strings.join(plain, " ", context.temp_allocator)
    testing.expect(t, strings.has_prefix(joined, "claude -p --input-format stream-json --output-format stream-json"))
    testing.expect(t, strings.contains(joined, "--setting-sources= --strict-mcp-config --mcp-config c.json --tools= --allowedTools mcp__amsg"))
    testing.expect(t, strings.contains(joined, "--append-system-prompt-file p.txt --model haiku"))
    for argument in plain {
        testing.expect(t, argument != "")                                   // an empty argument would be dropped on Windows
    }
    wider: string = strings.join(AgentCommand({tools = "Read,Glob", mcp_config = "c.json"}), " ", context.temp_allocator)
    testing.expect(t, strings.contains(wider, "--tools=Read,Glob --allowedTools mcp__amsg,Read,Glob"))
    testing.expect(t, !strings.contains(wider, "--model"))
}

// Lines that Claude Code printed for a real session (shortened), through AgentLine.
@(test)
AgentLineTest :: proc(t: ^testing.T) {
    agent: ^Agent = new(Agent)
    defer free(agent)
    lines: []string = {
        `{"type":"system","subtype":"init","cwd":"x","model":"claude-haiku-5-5","tools":[]}`,
        `{"type":"rate_limit_event","rate_limit_info":{}}`,
        `not json at all`,
        `{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"abc"},{"type":"text","text":"Hi there!"}]}}`,
        `{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"mcp__amsg__say","input":{"text":"hello group"}}]}}`,
        `{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"permission denied","is_error":true,"tool_use_id":"t1"}]}}`,
        `{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"fine","tool_use_id":"t1"}]}}`,
        `{"type":"result","subtype":"success","is_error":false,"result":"Hi there!","total_cost_usd":0.00062679}`,
        `{"type":"result","subtype":"error_during_execution","is_error":true,"result":"it broke","total_cost_usd":0.5}`,
    }
    for line in lines {
        AgentLine(agent, transmute([]byte)line)
        free_all(context.temp_allocator)
    }
    expected: [7]struct {
        kind: AgentEventKind,
        text: string,
    } = {
        {.READY, "claude-haiku-5-5"},
        {.TEXT, "Hi there!"},
        {.TOOL, `mcp__amsg__say {"text":"hello group"}`},
        {.TOOL_ERROR, "permission denied"},
        {.DONE, ""},
        {.DONE, "it broke"},
        {.NONE, ""},
    }
    for want, i in expected[:6] {
        event, ok := AgentPoll(agent)
        testing.expectf(t, ok, "event %d is missing", i)
        testing.expect_value(t, event.kind, want.kind)
        testing.expect_value(t, AgentEventText(&event), want.text)
        if i == 4 {
            testing.expect(t, !event.is_error && event.cost > 0.0006 && event.cost < 0.0007)
        }
        if i == 5 {
            testing.expect(t, event.is_error)
        }
    }
    _, more := AgentPoll(agent)
    testing.expect(t, !more)

    // a long answer comes as several events that together hold all of it
    long: string = strings.repeat("word ", 1000, context.temp_allocator)
    AgentPushText(agent, .TEXT, long)
    total: int
    pieces: int
    for {
        event, ok := AgentPoll(agent)
        if !ok {
            break
        }
        total += event.text_length
        pieces += 1
        testing.expect(t, event.text_length <= AGENT_TEXT_MAX)
    }
    testing.expect(t, pieces >= 3 && total >= 4900)
}

@(test)
JsonQuoteTest :: proc(t: ^testing.T) {
    testing.expect_value(t, JsonQuote("plain"), `"plain"`)
    testing.expect_value(t, JsonQuote("a \"quoted\" \\ line\nnext\ttab"), `"a \"quoted\" \\ line\nnext\ttab"`)
    testing.expect_value(t, JsonQuote("\x01"), `"\u0001"`)
    testing.expect_value(t, JsonQuote("héllo ✓"), `"héllo ✓"`)
}
