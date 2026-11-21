#+build !js
package demo_common

// Lines typed (or pasted) into the console that started the game: a host pastes the reply code of a guest there. A thread blocks on stdin and leaves each line in a one slot mailbox that the
// game takes once a frame (the same way as p2p/tool/chat); nothing else of the game is threaded.

import "core:os"
import "core:sync"
import "core:thread"

@(private = "file")
Mailbox :: struct {
    line: [1024]u8,
    length: int,
    full: bool,
    started: bool,
    lock: sync.Mutex,
}

@(private = "file")
mailbox: Mailbox

@(private = "file")
readLines :: proc() {
    buffer: [1024]u8
    for {
        count, error := os.read(os.stdin, buffer[:])
        if error != nil || count <= 0 { return }
        // wait for the game to take the previous line
        for {
            sync.mutex_lock(&mailbox.lock)
            if !mailbox.full { break }
            sync.mutex_unlock(&mailbox.lock)
        }
        mailbox.length = copy(mailbox.line[:], buffer[:count])
        mailbox.full = true
        sync.mutex_unlock(&mailbox.lock)
    }
}

consoleStart :: proc() {
    if mailbox.started { return }
    mailbox.started = true
    thread.create_and_start(readLines, context)
}

// The next line that was typed, without the line end; "" when there is none
consoleLine :: proc(buffer: []u8) -> string {
    if !mailbox.started { return "" }
    sync.mutex_lock(&mailbox.lock)
    defer sync.mutex_unlock(&mailbox.lock)
    if !mailbox.full { return "" }
    length: int = copy(buffer, mailbox.line[:mailbox.length])
    mailbox.full = false
    for length > 0 && (buffer[length - 1] == '\n' || buffer[length - 1] == '\r') { length -= 1 }
    return string(buffer[:length])
}
