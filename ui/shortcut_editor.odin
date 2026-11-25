package ui

// A page of shortcuts: every command of a program with the chord that does it, to set by pressing the keys (`UiShortcutField`), a button that puts the default back, a filter that narrows the list by the
// name of the command, and a note under a chord that another command has too.
//
//     commands: [3]ui.ShortcutCommand = {{"Save", {{.CTRL}, KEY_S}, {{.CTRL}, KEY_S}}, ...}
//     changed, listening := ui.UiShortcutEditor(&ctx, "Shortcuts", commands[:], pressed, key_name, filter[:], &filter_length)
//
// `pressed` and `key_name` are the ones of `UiShortcutField`. `changed` is the index of the command whose chord was set, taken away or reset in this frame (-1 for none); `listening` is true while a field waits for
// the keys: the program keeps its own shortcuts off then. The chords are the program's data (`commands[i].chord`): save them with its settings.
//
// Limits: one chord for a command (no second binding), no sequences, no groups or headings (the list is flat: a program that wants them puts several editors in a window), a conflict is shown and not
//     refused (the program decides what to do with two commands on a chord), the filter matches the name only (ASCII letters without regard to case), at most SHORTCUT_EDITOR_ROWS (256) commands are shown

SHORTCUT_EDITOR_ROWS :: 256

ShortcutCommand :: struct {
    name: string,                   // alive until UiRender
    chord: Chord,
    default: Chord,
}

// The command (other than `index`) that has the same chord, -1 for none; a command with no chord conflicts with nothing
ShortcutConflict :: proc(commands: []ShortcutCommand, index: int) -> int {
    chord: Chord = commands[index].chord
    if chord.key == 0 { return -1 }
    for other, i in commands {
        if i != index && other.chord == chord { return i }
    }
    return -1
}

UiShortcutEditor :: proc(ctx: ^Context, name: string, commands: []ShortcutCommand, pressed: Chord, key_name: proc(key: u16) -> string, filter: []u8, filter_length: ^int, size: Size = {}) -> (changed: int, listening: bool) {
    changed = -1
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {id = UiId(ctx, name), layout = {size = widgetSizeOr(size, Fixed(metrics.control_width * 3.6), Fixed(metrics.control_height * 9)), direction = .TOP_TO_BOTTOM, gap = metrics.gap}})
    defer ElementClose(ctx)
    UiTextField(ctx, "##filter", filter, filter_length, {Grow(), {}})
    query: string = string(filter[:clamp(filter_length^, 0, len(filter))])
    if UiScroll(ctx, "##list", {Grow(), Grow()}, {padding = PaddingAll(4), gap = 4}) {
        shown: int
        for command, i in commands {
            if i >= SHORTCUT_EDITOR_ROWS { break }
            if len(query) > 0 && completeFind(command.name, query) < 0 { continue }
            shown += 1
            if UiRow(ctx, {size = {Grow(), Fit()}, gap = metrics.gap, align = {y = .CENTER}}) {
                UiLabel(ctx, command.name)
                UiSpacer(ctx)
                chord: ^Chord = &commands[i].chord
                field_changed, field_listening := UiShortcutField(ctx, UiFormat(ctx, "##chord%d", i), chord, pressed, key_name, {Fixed(metrics.control_width * 1.3), {}})
                if field_changed { changed = i }
                listening = listening || field_listening
                if UiDisabled(ctx, command.chord == command.default) {
                    if UiButton(ctx, UiFormat(ctx, "Reset##reset%d", i)) {
                        chord^ = command.default
                        changed = i
                    }
                }
            }
            if other: int = ShortcutConflict(commands, i); other >= 0 {
                UiLabelDim(ctx, UiFormat(ctx, "also used by %s", commands[other].name), .NONE, 0.85)
            }
        }
        if shown == 0 { UiLabelDim(ctx, "No command matches") }
    }
    return
}
