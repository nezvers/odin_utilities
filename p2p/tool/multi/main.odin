// Starts one host and several guests of the chat as separate processes, hands the codes between them like a person would
// (copy, paste), prints everything they say in one merged, timestamped log, and checks that every instance heard every other one.
//
//   odin run p2p/tool/multi                    3 instances (host + 2 guests) on this computer
//   odin run p2p/tool/multi -- 5               5 instances
//   odin run p2p/tool/multi -- 3 --wireguard-dry --no-ipv6     more words after the count go to every chat program
//
// Exit code 0 when every instance received the hello of every other instance, 1 otherwise (and the log says who missed what).
// It always adds --loopback --no-stun: it tests the program flow and the many-peer logic, not the NAT (that is the simulation's job
// and the real two-network test).
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

MAX_INSTANCES :: 8                      // p2p.MAX_PEERS: the host plus seven guests
LINE_MAX :: 1024
QUEUE :: 512
TIMEOUT_MS :: 60000
EXIT_WAIT_MS :: 4000

Instance :: struct {
    index: int,
    name: string,
    process: os.Process,
    input: ^os.File,                    // the chat's stdin (our write end)
    output: ^os.File,                   // its stdout and stderr (our read end)
    thread: ^thread.Thread,
    code_sent: bool,                    // host: its code was given to the guests. guest: its reply was given to the host
    connected: int,                     // "* X connected" lines seen
    hello_sent: bool,
    heard: [MAX_INSTANCES]bool,         // heard[j]: saw "hello from <name of j>"
    finished: bool,                     // the output ended (the process exited)
}

Line :: struct {
    instance: int,
    text: [LINE_MAX]byte,
    length: int,
}

instances: [MAX_INSTANCES]Instance
count: int
queue: [QUEUE]Line
queue_head: int
queue_count: int
queue_mutex: sync.Mutex
start: time.Tick

main :: proc() {
    count = 3
    extra: [dynamic]string
    extra_flags: bool
    for i := 1; i < len(os.args); i += 1 {
        if !extra_flags {
            number, ok := strconv.parse_int(os.args[i])
            if ok {
                count = number
                extra_flags = true
                continue
            }
        }
        extra_flags = true
        append(&extra, os.args[i])
    }
    if count < 2 || count > MAX_INSTANCES {
        fmt.eprintfln("the number of instances must be 2..%d", MAX_INSTANCES)
        os.exit(2)
    }

    exe: string = Build()
    start = time.tick_now()
    for i in 0 ..< count {
        Launch(i, exe, extra[:])
    }
    Log(-1, fmt.tprintf("%d instances started, waiting for the host's code", count))

    ok: bool = Run()
    Shutdown()
    Report(ok)
    os.exit(0 if ok else 1)
}

// Compiles the chat once, so a failed build is reported before anything starts.
Build :: proc() -> string {
    folder, error := os.temp_directory(context.allocator)
    if error != nil {
        folder = "."
    }
    path: string = fmt.aprintf("%s/p2p_multi_chat%s", strings.trim_right(folder, "/\\"), ".exe" when ODIN_OS == .Windows else "")
    fmt.printfln("building the chat program -> %s", path)
    state, stdout, stderr, exec_error := os.process_exec({command = {"odin", "build", "p2p/tool/chat", fmt.tprintf("-out:%s", path), "-o:speed"}}, context.temp_allocator)
    if exec_error != nil || state.exit_code != 0 {
        fmt.eprintfln("build failed (run this from the odin_utilities folder):\n%s%s", string(stdout), string(stderr))
        os.exit(2)
    }
    return path
}

Launch :: proc(index: int, exe: string, extra: []string) {
    instance: ^Instance = &instances[index]
    instance.index = index
    instance.name = "Host" if index == 0 else fmt.aprintf("G%d", index)

    stdin_read, stdin_write, stdin_error := os.pipe()
    stdout_read, stdout_write, stdout_error := os.pipe()
    if stdin_error != nil || stdout_error != nil {
        fmt.eprintln("cannot make pipes")
        os.exit(2)
    }
    command: [dynamic]string
    append(&command, exe, "host" if index == 0 else "join", instance.name, "--loopback", "--no-stun")
    for word in extra {
        append(&command, word)
    }
    process, error := os.process_start({command = command[:], stdin = stdin_read, stdout = stdout_write, stderr = stdout_write})
    if error != nil {
        fmt.eprintfln("cannot start %s: %v", exe, error)
        os.exit(2)
    }
    // our copies of the child's ends are closed, so the reader sees the end of the output when the child exits
    os.close(stdin_read)
    os.close(stdout_write)
    instance.process = process
    instance.input = stdin_write
    instance.output = stdout_read
    instance.thread = thread.create_and_start_with_data(instance, ReadOutput)
}

// One thread per instance: a blocked read must not stop the others.
ReadOutput :: proc(data: rawptr) {
    instance: ^Instance = cast(^Instance)data
    chunk: [512]byte
    line: [LINE_MAX]byte
    length: int
    for {
        read, error := os.read(instance.output, chunk[:])
        if error != nil || read <= 0 {
            break
        }
        for b in chunk[:read] {
            switch b {
            case '\n':
                Push(instance.index, line[:length])
                length = 0
            case '\r':
            case:
                if length < len(line) {
                    line[length] = b
                    length += 1
                }
            }
        }
    }
    if length > 0 {
        Push(instance.index, line[:length])
    }
    Push(instance.index, nil, true)     // the end of the output (a blank line from the program is a normal line)
}

Push :: proc(instance: int, text: []byte, ended: bool = false) {
    for {
        sync.mutex_lock(&queue_mutex)
        if queue_count < QUEUE {
            slot: ^Line = &queue[(queue_head + queue_count) % QUEUE]
            slot.instance = instance
            slot.length = -1 if ended else len(text)
            copy(slot.text[:], text)
            queue_count += 1
            sync.mutex_unlock(&queue_mutex)
            return
        }
        sync.mutex_unlock(&queue_mutex)
        time.sleep(time.Millisecond)
    }
}

Pop :: proc(out: ^Line) -> bool {
    sync.mutex_lock(&queue_mutex)
    defer sync.mutex_unlock(&queue_mutex)
    if queue_count == 0 {
        return false
    }
    out^ = queue[queue_head]
    queue_head = (queue_head + 1) % QUEUE
    queue_count -= 1
    return true
}

Elapsed :: proc() -> i64 {
    return i64(time.duration_milliseconds(time.tick_since(start)))
}

// One line of the merged log: time since the start, who said it.
Log :: proc(instance: int, text: string) {
    who: string = "multi" if instance < 0 else instances[instance].name
    fmt.printfln("[%6dms] [%-5s] %s", Elapsed(), who, text)
}

Say :: proc(instance: ^Instance, text: string) {
    os.write_string(instance.input, text)
    os.write_string(instance.input, "\n")
}

// The conductor: reads what the programs print and does what the person would do. True when everybody heard everybody.
Run :: proc() -> bool {
    line: Line
    for Elapsed() < TIMEOUT_MS {
        got: bool
        for Pop(&line) {
            got = true
            Handle(&line)
        }
        if AllConnected() {
            for i in 0 ..< count {
                if !instances[i].hello_sent {
                    instances[i].hello_sent = true
                    Say(&instances[i], fmt.tprintf("hello from %s", instances[i].name))
                }
            }
        }
        if AllHeard() {
            Log(-1, "everybody heard everybody")
            return true
        }
        if !got {
            time.sleep(5 * time.Millisecond)
        }
    }
    Log(-1, fmt.tprintf("timeout after %d ms", TIMEOUT_MS))
    return false
}

Handle :: proc(line: ^Line) {
    instance: ^Instance = &instances[line.instance]
    if line.length < 0 {
        instance.finished = true
        Log(line.instance, "(output ended)")
        return
    }
    text: string = string(line.text[:line.length])
    if line.length == 0 {
        return
    }
    Log(line.instance, text)
    switch {
    case strings.has_prefix(text, "CODE: "):
        code: string = strings.clone(text[len("CODE: "):], context.temp_allocator)
        if line.instance == 0 {
            // the host's invite goes to every guest
            if !instance.code_sent {
                instance.code_sent = true
                for i in 1 ..< count {
                    Say(&instances[i], code)
                }
            }
        } else if !instance.code_sent {
            // a guest's reply goes to the host
            instance.code_sent = true
            Say(&instances[0], code)
        }
    case strings.has_suffix(text, " connected") && strings.has_prefix(text, "* "):
        // the host sees every guest and passes the news on, so only its own line counts
        peer: string = text[2:len(text) - len(" connected")]
        if line.instance == 0 && peer != "Host" || line.instance != 0 && peer == "Host" {
            instance.connected += 1
        }
    case:
        for j in 0 ..< count {
            if j != line.instance && strings.contains(text, fmt.tprintf("hello from %s", instances[j].name)) {
                instance.heard[j] = true
            }
        }
    }
}

AllConnected :: proc() -> bool {
    if instances[0].connected < count - 1 {
        return false
    }
    for i in 1 ..< count {
        if instances[i].connected < 1 {
            return false
        }
    }
    return true
}

AllHeard :: proc() -> bool {
    for i in 0 ..< count {
        for j in 0 ..< count {
            if i != j && !instances[i].heard[j] {
                return false
            }
        }
    }
    return true
}

Shutdown :: proc() {
    for i in 0 ..< count {
        Say(&instances[i], "/quit")
    }
    deadline: i64 = Elapsed() + EXIT_WAIT_MS
    line: Line
    for Elapsed() < deadline {
        for Pop(&line) {
            if line.length < 0 {
                instances[line.instance].finished = true
            } else {
                Log(line.instance, string(line.text[:line.length]))
            }
        }
        done: bool = true
        for i in 0 ..< count {
            done &&= instances[i].finished
        }
        if done {
            break
        }
        time.sleep(5 * time.Millisecond)
    }
    for i in 0 ..< count {
        if !instances[i].finished {
            Log(i, "did not exit, killing it")
            _ = os.process_kill(instances[i].process)
        }
        _, _ = os.process_wait(instances[i].process)
    }
}

Report :: proc(ok: bool) {
    fmt.println()
    fmt.printfln("---- %d instances, %d ms ----", count, Elapsed())
    for i in 0 ..< count {
        missing: [dynamic]string
        for j in 0 ..< count {
            if i != j && !instances[i].heard[j] {
                append(&missing, instances[j].name)
            }
        }
        if len(missing) == 0 {
            fmt.printfln("%-5s connected %d, heard everybody", instances[i].name, instances[i].connected)
        } else {
            fmt.printfln("%-5s connected %d, MISSED the hello of %s", instances[i].name, instances[i].connected, strings.join(missing[:], ", ", context.temp_allocator))
        }
    }
    fmt.println("PASS" if ok else "FAIL")
}
