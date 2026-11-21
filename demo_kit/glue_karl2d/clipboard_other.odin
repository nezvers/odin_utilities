#+build !windows
package demo_kit_karl2d

// No system clipboard for the Karl2D backend here: the kit keeps a copy inside of the program.

systemClipboardGet :: proc(buffer: []u8) -> int {
    return 0
}

systemClipboardSet :: proc(text: string) {
}
