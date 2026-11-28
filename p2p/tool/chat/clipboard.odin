package main

import "core:os"

// Puts text on the system clipboard through the tool every desktop has (clip, pbcopy, xclip). The library itself does not
// touch the clipboard: a game would use its framework (raylib SetClipboardText, Karl2D) and pass the code text in.
//
// The text goes in through a temp file given as the child's stdin, not a pipe: a pipe's write end is inherited by the child on
// Windows, it never sees the end of its input and the wait never returns.
ClipboardSet :: proc(text: string) -> bool {
    command: []string
    when ODIN_OS == .Windows {
        command = {"clip"}
    } else when ODIN_OS == .Darwin {
        command = {"pbcopy"}
    } else {
        command = {"xclip", "-selection", "clipboard"}
    }
    file, file_error := os.create_temp_file("", "p2p_code_*.txt")
    if file_error != nil {
        return false
    }
    path: string = os.name(file)
    defer os.remove(path)
    defer os.close(file)
    if _, write_error := os.write_string(file, text); write_error != nil {
        return false
    }
    if _, seek_error := os.seek(file, 0, .Start); seek_error != nil {
        return false
    }
    process, start_error := os.process_start({command = command, stdin = file})
    if start_error != nil {
        return false
    }
    state, wait_error := os.process_wait(process)
    return wait_error == nil && state.exit_code == 0
}
