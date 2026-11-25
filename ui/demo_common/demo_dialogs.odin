#+private file
package demo_common

// The ready made windows of ui/dialogs.odin: a question with three buttons, the about window, the welcome screen, a progress window and the preferences window with a page per category.
// The script opens the preferences, switches the page and changes a setting, then answers the question.

import "core:reflect"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_dialogs: kit.Demo = {
    name = "dialogs",
    init = init,
    draw = draw,
    script = script,
}

CATEGORIES: [3]string = {"General", "Audio", "Shortcuts"}
RELEASES: [3]ui.Release = {
    {"0.60.1", "2026-11-20", "- **Fixed** a click through the preferences window\n- Faster waveform drawing"},
    {"0.60", "2026-11-02", "- New **modulation matrix**\n- Skins can name their fonts\n- Shortcuts page in the preferences"},
    {"0.59", "2026-10-15", "- First public build"},
}
RECENT: [3]string = {"Night drive.nota", "Sketch 4.nota", "Drums only.nota"}
ACTIONS: [2]string = {"New project", "Open..."}

State :: struct {
    app: UiDemo,
    prefs: bool,
    confirm: bool,
    about: bool,
    welcome: bool,
    progress: bool,
    news: bool,
    page: int,
    autosave: bool,
    buffer: f32,
    answer: int,
    action: int,
    recent: int,
    fraction: f32,
    commands: [4]ui.ShortcutCommand,
    filter: [24]u8,
    filter_length: int,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {autosave = true, buffer = 0.4, answer = -1, action = -1, recent = -1, fraction = 0.35}
    state.commands = {{"Save", {{.CTRL}, u16(kit.Key.S)}, {{.CTRL}, u16(kit.Key.S)}}, {"Open", {{.CTRL}, u16(kit.Key.O)}, {{.CTRL}, u16(kit.Key.O)}}, {"Find", {{.CTRL}, u16(kit.Key.F)}, {{.CTRL}, u16(kit.Key.F)}}, {"Close", {}, {{.CTRL}, u16(kit.Key.W)}}}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "dialogs", {size = {ui.Fixed(520), ui.Fixed(200)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        if ui.UiRow(c, {gap = 8}) {
            if ui.UiButton(c, "Preferences") { state.prefs = true }
            if ui.UiButton(c, "Save?") { state.confirm = true }
            if ui.UiButton(c, "About") { state.about = true }
            if ui.UiButton(c, "Welcome") { state.welcome = true }
            if ui.UiButton(c, "Export") { state.progress = true }
            if ui.UiButton(c, "News") { state.news = true }
        }
        ui.UiLabelf(c, "answer %d, action %d, recent %d", state.answer, state.action, state.recent)
    }
    if ui.UiPreferences(c, "Preferences", &state.prefs, CATEGORIES[:], &state.page, {ui.Fixed(520), ui.Fixed(320)}) {
        switch state.page {
        case 0:
            ui.UiToggle(c, "Save automatically", &state.autosave)
        case 1:
            ui.UiLabelDim(c, "Buffer size")
            ui.UiSlider(c, "Buffer", &state.buffer, 0, 1, {ui.Grow(), {}})
        case 2:
            pressed: ui.Chord = {modifiers = c.input.modifiers}
            for key in kit.Key {
                if key == .None || (key >= .LEFT_SHIFT && key <= .RIGHT_ALT) || key not_in ctx.input.keys_pressed { continue }
                pressed.key = u16(key)
                break
            }
            ui.UiShortcutEditor(c, "Keys", state.commands[:], pressed, proc(key: u16) -> string { return reflect.enum_string(kit.Key(key)) }, state.filter[:], &state.filter_length, {ui.Grow(), ui.Grow()})
        }
    }
    if answer := ui.UiConfirm(c, "Save changes?", &state.confirm, "The project has changes that are not saved.", {"Save", "Don't save", "Cancel"}, icon = ui_default.LucideIcon(.TRIANGLE_ALERT)); answer >= 0 { state.answer = answer }
    ui.UiAboutDialog(c, "About", &state.about, {name = "Nota", version = "0.60.1", description = "A small DAW made with the ui library.", credits = "Layout from Clay, the look follows Baldr.", copyright = "2026", icon = ui_default.LucideIcon(.INFO)})
    if action, recent := ui.UiWelcome(c, "Welcome", &state.welcome, {headline = "Nota", tagline = "Pick up where you left off.", actions = ACTIONS[:], recent = RECENT[:]}); action >= 0 || recent >= 0 {
        state.action, state.recent = action, recent
    }
    ui.UiWhatsNew(c, "What is new", &state.news, RELEASES[:], ui.WhatsNewUnseen(RELEASES[:], "0.60"))
    if ui.UiProgressDialog(c, "Exporting", &state.progress, "Writing the mix to disk...", state.fraction) { state.progress = false }
    ui_demo_end(&state.app)
}

target: ui.Vec2

button :: proc(name: string) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath("dialogs", name))
    if found { target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5} }
    return found
}

inside :: proc(window: string, name: string) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath(window, name))
    if found { target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5} }
    return found
}

inside3 :: proc(window: string, container: string, name: string) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath(window, container, name))
    if found { target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5} }
    return found
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return button("Preferences") }, "the Preferences button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.prefs && inside3("Preferences", "##categories", "Audio##cat1") }, "the category Audio"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.page == 1 }, "a click on a category shows its page"),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("dialogs_preferences"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return inside3("Preferences", "##categories", "Shortcuts##cat2") }, "the category Shortcuts"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("dialogs_shortcuts"),
    kit.Wait(2),
    kit.Tap(.ESCAPE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.prefs }, "Escape closes the window"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return button("Save?") }, "the Save? button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("dialogs_confirm"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.confirm && inside("Save changes?", "Don't save") }, "the middle button"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.answer == 1 && !state.confirm }, "a button answers and closes"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return button("News") }, "the News button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("dialogs_news"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.news && inside("What is new", "Close") }, "the Close button of the news"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.news }, "Close closes it"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return button("Welcome") }, "the Welcome button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("dialogs_welcome"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return inside("Welcome", "Sketch 4.nota##recent1") }, "a recent file"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.recent == 1 && !state.welcome }, "a click on a recent file picks it"),
}
