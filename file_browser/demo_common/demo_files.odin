#+private file
package demo_common

// Open a picture and a sound with the file browser, show the picture, play the sound, change both and save them back. The label under the buttons says what the browser is doing and what went wrong.
//   - desktop: the dialog of the library (file_browser.UiFileBrowser) browsing the disk, with the folders it remembers
//   - web page: the file chooser of the browser and a download (the same calls, `IoPlatform` picks)
//   - scripted run (a headless test or kit.DEMO_TEST): a file system in memory with a few files of `assets/`, so the same files and paths on every machine
// What the program does with a file is the demo's own: decode the picture, turn it around in memory (invert), encode it as PNG, make a tone as a WAV: the formats that raylib and Karl2D both open.

import "core:fmt"
import "core:image"
import _ "core:image/bmp"
import _ "core:image/jpeg"
import "core:image/png"
import "core:math"
import fb ".."
import ui "../../ui"
import ui_default "../../ui/default_style"
import ui_kit "../../ui/kit"
import kit "../../demo_kit"

@(private = "package")
demo_files: kit.Demo = {
    name = "files",
    init = init,
    finit = finit,
    draw = draw,
    script = script,
}

DATA_CAPACITY :: 4 * 1024 * 1024           // the biggest picture and the biggest sound that can be opened: a bigger file is an error of the browser (TOO_BIG)
TONE_RATE :: 22050
TONE_SECONDS :: 0.6

// the filters: what the dropdown of the dialog offers and what the chooser of a web page is told. Pictures that raylib and Karl2D both read, sounds the same.
PICTURE_FILTERS: [2]fb.Filter = {{name = "Pictures (png, jpg, bmp)", extensions = {"png", "jpg", "jpeg", "bmp"}}, {name = "PNG only", extensions = {"png"}}}
SOUND_FILTERS: [2]fb.Filter = {{name = "Sounds (wav, ogg)", extensions = {"wav", "ogg"}}, {name = "All files"}}

Request :: enum {
    NONE,
    OPEN_PICTURE,
    OPEN_SOUND,
    SAVE_PICTURE,
    SAVE_SOUND,
}

State :: struct {
    storage: ui.Storage(512, 1024, 128, 8192),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
    kit_ctx: ^kit.Context,

    browser: fb.FileBrowser,
    entries: [256]fb.Entry,
    names: [16384]u8,
    fs: fb.MemoryFs,                        // the files of a scripted run
    fs_files: [32]fb.MemoryFile,
    fs_storage: [256 * 1024]u8,
    request: Request,
    same_folder: bool,

    picture_bytes: [DATA_CAPACITY]u8,       // the file as it was opened, or as the program made it
    picture_size: int,
    picture_name: [fb.NAME_MAX]u8,
    picture_name_length: int,
    texture: kit.Texture,
    texture_size: kit.Vec2,
    save_extension: [16]u8,                 // the filter of a save is the format of the picture
    save_extension_text: [1]string,
    save_filters: [1]fb.Filter,

    sound_bytes: [DATA_CAPACITY]u8,
    sound_size: int,
    sound_name: [fb.NAME_MAX]u8,
    sound_name_length: int,
    sound: kit.Sound,
    plays: int,

    notice: [200]u8,                        // what the program itself says went wrong (a file that is not a picture)
    notice_length: int,
    status: [320]u8,
}

state: ^State

init :: proc(ctx: ^kit.Context) {
    state = new(State)
    ui_kit.PainterInit(&state.painter)
    state.style = ui_default.StyleMake()
    ui.UiInit(&state.ctx, &state.storage, ui_default.Measure, &state.painter)
    ctx.background = {17, 19, 21, 255}
    state.same_folder = true

    io: fb.Io
    memory: bool = ctx.backend.headless || kit.DEMO_TEST
    if memory {
        fb.MemoryFsInit(&state.fs, state.fs_files[:], state.fs_storage[:])
        fb.MemoryFsAdd(&state.fs, "/demo/pictures/player_sheet.png", #load("../../assets/textures/player_sheet.png"))
        fb.MemoryFsAdd(&state.fs, "/demo/pictures/tileset_template.png", #load("../../assets/textures/tileset_template.png"))
        fb.MemoryFsAdd(&state.fs, "/demo/pictures/notes.txt", []u8{'h', 'i'})
        fb.MemoryFsAdd(&state.fs, "/demo/pictures/old/palette.png", #load("../../assets/textures/palette_journey.png"))
        fb.MemoryFsAdd(&state.fs, "/demo/sounds/button_sound.wav", #load("../../assets/sounds/button_sound.wav"))
        fb.MemoryFsAdd(&state.fs, "/demo/sounds/damage_sound.wav", #load("../../assets/sounds/damage_sound.wav"))
        fb.MemoryFsDirectory(&state.fs, "/demo/saved")
        io = fb.IoMemory(&state.fs)
    } else {
        io = fb.IoPlatform()
    }
    fb.FileBrowserInit(&state.browser, io, state.entries[:], state.names[:])
    if memory { fb.FileBrowserSetDirectories(&state.browser, "/demo/pictures", "") }
}

finit :: proc(ctx: ^kit.Context) {
    if state.texture != kit.TEXTURE_NONE { kit.TextureUnload(ctx, state.texture) }
    if state.sound != kit.SOUND_NONE { kit.SoundUnload(ctx, state.sound) }
    free(state)
    state = nil
}

draw :: proc(ctx: ^kit.Context) {
    state.kit_ctx = ctx
    ui_kit.Begin(&state.ctx, &state.painter, &state.style, ctx)
    c: ^ui.Context = &state.ctx
    browser: ^fb.FileBrowser = &state.browser
    busy: bool = browser.state == .BROWSING || browser.state == .PICKING
    if ui.UiPanel(c, "files", {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(14), gap = 10}) {
        ui.UiTitle(c, "File browser: open a picture and a sound, change them, save them back")
        if ui.UiRow(c, {gap = 8, size = {ui.Grow(), {}}}) {
            if ui.UiButton(c, "Open picture...##open_picture", {}, busy) { openPicture() }
            if ui.UiButton(c, "Open sound...##open_sound", {}, busy) { openSound() }
            if ui.UiButton(c, "Save picture as...##save_picture", {}, busy || state.picture_size == 0) { savePicture() }
            if ui.UiButton(c, "Save sound as...##save_sound", {}, busy || state.sound_size == 0) { saveSound() }
        }
        if ui.UiRow(c, {gap = 8, size = {ui.Grow(), {}}}) {
            if ui.UiButton(c, "Invert picture##invert", {}, busy || state.picture_size == 0) { invertPicture(ctx) }
            if ui.UiButton(c, "Make a tone##tone", {}, busy) { makeTone(ctx) }
            if ui.UiButton(c, "Play sound##play", {}, state.sound == kit.SOUND_NONE) { play(ctx) }
            ui.UiSpacer(c)
            if ui.UiSwitch(c, "Open and save start in the same folder##same", &state.same_folder) {
                fb.FileBrowserSetMemory(browser, .SHARED if state.same_folder else .SEPARATE)
            }
        }
        if ui.UiRow(c, {gap = 14}) {
            drawPicture(c)
            if ui.UiColumn(c, {gap = 6, size = {ui.Grow(), {}}}) {
                ui.UiLabelDim(c, "Picture")
                ui.UiLabel(c, picture_text(), .WORDS)
                ui.UiLabelDim(c, "Sound")
                ui.UiLabel(c, sound_text(), .WORDS)
                ui.UiLabelDim(c, "Next open starts in")
                ui.UiLabel(c, directories_text(), .WORDS)
            }
        }
        ui.UiSeparator(c)
        ui.UiLabel(c, fmt.tprintf("State: %v. %s", browser.state, fb.FileBrowserStatus(browser, state.status[:])), .WORDS)
        ui.UiLabel(c, error_text(), .WORDS)
    }
    result: fb.Result = fb.UiFileBrowser(c, browser)
    if result.kind == .OPENED {
        #partial switch state.request {
        case .OPEN_PICTURE: openedPicture(ctx, result.path, len(result.data))
        case .OPEN_SOUND: openedSound(ctx, result.path, len(result.data))
        }
    }
    ui.UiEnd(c)
    ui.UiRender(c)
}

// ------------------------------------------------------------------------------------------------------------------------
// What the buttons do

openPicture :: proc() {
    state.request = .OPEN_PICTURE
    state.notice_length = 0
    fb.FileBrowserOpen(&state.browser, state.picture_bytes[:], PICTURE_FILTERS[:])
}

openSound :: proc() {
    state.request = .OPEN_SOUND
    state.notice_length = 0
    fb.FileBrowserOpen(&state.browser, state.sound_bytes[:], SOUND_FILTERS[:])
}

// The picture is saved in the format it has: the filter of the dialog is its extension
savePicture :: proc() {
    state.request = .SAVE_PICTURE
    state.notice_length = 0
    name: string = string(state.picture_name[:state.picture_name_length])
    extension: string = fb.PathExtension(name)
    state.save_extension_text[0] = string(state.save_extension[:copy(state.save_extension[:], extension)])
    state.save_filters[0] = {name = "Same format as the picture", extensions = state.save_extension_text[:]}
    fb.FileBrowserSave(&state.browser, state.picture_bytes[:state.picture_size], name, state.save_filters[:])
}

saveSound :: proc() {
    state.request = .SAVE_SOUND
    state.notice_length = 0
    fb.FileBrowserSave(&state.browser, state.sound_bytes[:state.sound_size], string(state.sound_name[:state.sound_name_length]), SOUND_FILTERS[:1])
}

play :: proc(ctx: ^kit.Context) {
    kit.SoundPlay(ctx, state.sound)
    state.plays += 1
}

openedPicture :: proc(ctx: ^kit.Context, path: string, size: int) {
    state.picture_size = size
    state.picture_name_length = copy(state.picture_name[:], fb.PathFileName(path))
    showPicture(ctx)
}

// The backend decides what it can read: a file with the right extension and the wrong content is the program's error, not the browser's
showPicture :: proc(ctx: ^kit.Context) {
    if state.texture != kit.TEXTURE_NONE { kit.TextureUnload(ctx, state.texture) }
    state.texture = kit.TextureLoad(ctx, state.picture_bytes[:state.picture_size])
    if state.texture == kit.TEXTURE_NONE {
        say("%s is not a picture that this program can read", string(state.picture_name[:state.picture_name_length]))
        state.picture_size = 0
        state.texture_size = {}
        return
    }
    state.texture_size = kit.TextureSize(ctx, state.texture)
}

openedSound :: proc(ctx: ^kit.Context, path: string, size: int) {
    state.sound_size = size
    state.sound_name_length = copy(state.sound_name[:], fb.PathFileName(path))
    showSound(ctx)
}

showSound :: proc(ctx: ^kit.Context) {
    if state.sound != kit.SOUND_NONE { kit.SoundUnload(ctx, state.sound) }
    state.sound = kit.SoundLoad(ctx, state.sound_bytes[:state.sound_size])
    if state.sound == kit.SOUND_NONE {
        say("%s is not a sound that this program can play", string(state.sound_name[:state.sound_name_length]))
        state.sound_size = 0
    }
}

// The pixels are decoded here, inverted in memory and encoded as a PNG again: the file the program saves is not the file it opened
invertPicture :: proc(ctx: ^kit.Context) {
    state.notice_length = 0
    decoded, decode_error := image.load_from_bytes(state.picture_bytes[:state.picture_size], {.alpha_add_if_missing})
    if decode_error != nil {
        say("%s cannot be decoded: %v", string(state.picture_name[:state.picture_name_length]), decode_error)
        return
    }
    defer image.destroy(decoded)
    if decoded.depth != 8 || decoded.channels != 4 {
        say("only 8 bit pictures can be inverted here")
        return
    }
    pixels: []u8 = decoded.pixels[:]
    for i := 0; i + 3 < len(pixels); i += 4 {
        pixels[i], pixels[i + 1], pixels[i + 2] = 255 - pixels[i], 255 - pixels[i + 1], 255 - pixels[i + 2]
    }
    encoded: [dynamic]u8
    defer delete(encoded)
    if encode_error := png.save_to_buffer(&encoded, decoded); encode_error != nil {
        say("the picture cannot be encoded: %v", encode_error)
        return
    }
    if len(encoded) > len(state.picture_bytes) {
        say("the inverted picture is too big for the buffer")
        return
    }
    copy(state.picture_bytes[:], encoded[:])
    state.picture_size = len(encoded)
    stem: string = string(state.picture_name[:state.picture_name_length])
    if dot := fb.PathExtension(stem); len(dot) > 0 { stem = stem[:len(stem) - len(dot) - 1] }
    state.picture_name_length = len(fmt.bprintf(state.picture_name[:], "%s_inverted.png", stem))
    showPicture(ctx)
}

// 0.6 seconds of a 440 Hz sine that dies away, as a 16 bit mono WAV file
makeTone :: proc(ctx: ^kit.Context) {
    state.notice_length = 0
    samples: int = int(TONE_RATE * TONE_SECONDS)
    bytes: []u8 = state.sound_bytes[:]
    put :: proc(bytes: []u8, at: int, value: u32, count: int) {
        for i in 0 ..< count { bytes[at + i] = u8(value >> u32(8 * i)) }
    }
    copy(bytes[0:], "RIFF")
    put(bytes, 4, u32(36 + samples * 2), 4)
    copy(bytes[8:], "WAVEfmt ")
    put(bytes, 16, 16, 4)                   // the size of the format chunk
    put(bytes, 20, 1, 2)                    // PCM
    put(bytes, 22, 1, 2)                    // mono
    put(bytes, 24, TONE_RATE, 4)
    put(bytes, 28, TONE_RATE * 2, 4)        // bytes a second
    put(bytes, 32, 2, 2)                    // bytes a frame
    put(bytes, 34, 16, 2)                   // bits a sample
    copy(bytes[36:], "data")
    put(bytes, 40, u32(samples * 2), 4)
    for i in 0 ..< samples {
        t: f32 = f32(i) / TONE_RATE
        value: f32 = math.sin(2 * math.PI * 440 * t) * math.exp(-4 * t) * 0.6
        put(bytes, 44 + i * 2, u32(u16(i16(value * 32767))), 2)
    }
    state.sound_size = 44 + samples * 2
    state.sound_name_length = copy(state.sound_name[:], "tone.wav")
    showSound(ctx)
    if state.sound != kit.SOUND_NONE { play(ctx) }
}

say :: proc(format: string, args: ..any) {
    state.notice_length = len(fmt.bprintf(state.notice[:], format, ..args))
}

// ------------------------------------------------------------------------------------------------------------------------
// What is on the screen

picture_text :: proc() -> string {
    if state.picture_size == 0 { return "none yet" }
    return fmt.tprintf("%s: %d x %d, %d bytes", string(state.picture_name[:state.picture_name_length]), int(state.texture_size.x), int(state.texture_size.y), state.picture_size)
}

sound_text :: proc() -> string {
    if state.sound_size == 0 { return "none yet" }
    return fmt.tprintf("%s: %d bytes, played %d times", string(state.sound_name[:state.sound_name_length]), state.sound_size, state.plays)
}

directories_text :: proc() -> string {
    open, save := fb.FileBrowserDirectories(&state.browser)
    if len(open) == 0 && len(save) == 0 { return "the home folder (nothing remembered yet)" }
    if state.browser.memory == .SHARED { return fmt.tprintf("%s (open and save)", open) }
    return fmt.tprintf("open: %s, save: %s", open if len(open) > 0 else "home", save if len(save) > 0 else "home")
}

// The error of the browser while its dialog is open, else the program's own, else none
error_text :: proc() -> string {
    browser: ^fb.FileBrowser = &state.browser
    if browser.error != .NONE { return fmt.tprintf("Error: %s", string(browser.message[:browser.message_length])) }
    if state.notice_length > 0 { return fmt.tprintf("Error: %s", string(state.notice[:state.notice_length])) }
    return "Error: none"
}

PICTURE_WIDTH :: 560
PICTURE_HEIGHT :: 320

drawPicture :: proc(c: ^ui.Context) {
    ui.ElementOpen(c, {
        id = ui.UiId(c, "picture"),
        layout = {size = {ui.Fixed(PICTURE_WIDTH), ui.Fixed(PICTURE_HEIGHT)}},
        draw = {kind = .CUSTOM, custom = picture_draw, texture = u32(state.texture), actual = state.texture_size.x, maximum = state.texture_size.y},
    })
    ui.ElementClose(c)
}

// The picture fitted into its frame, as big as fits (a small picture is magnified, pixels stay square)
picture_draw :: proc(c: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = ui_default.PainterOf(c)
    painter.fill_rect(painter, info.rect, painter.theme.track_strong)
    if info.texture == 0 || info.actual <= 0 || info.maximum <= 0 || painter.draw_texture == nil { return }
    scale: f32 = min(info.rect.z / info.actual, info.rect.w / info.maximum)
    size: ui.Vec2 = {info.actual * scale, info.maximum * scale}
    fitted: ui.Rect = {info.rect.x + (info.rect.z - size.x) * 0.5, info.rect.y + (info.rect.w - size.y) * 0.5, size.x, size.y}
    painter.draw_texture(painter, info.texture, {}, fitted, {255, 255, 255, 255})
}

// ------------------------------------------------------------------------------------------------------------------------
// The script: a person with a mouse and a keyboard, over the files in memory

target: ui.Vec2

find :: proc(path: ..string) -> bool {
    rect, found := ui.UiElementRect(&state.ctx, ui.UiIdPath(..path))
    if found { target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5} }
    return found
}

// the middle of a row of the list of files of the dialog
findRow :: proc(row: int) -> bool {
    rect, found := ui.UiElementRect(&state.ctx, ui.UiIdPath(DIALOG, "##files"))
    if found { target = {rect.x + rect.z * 0.5, rect.y + (f32(row) + 0.5) * fb.FILE_ROW_HEIGHT} }
    return found
}

DIALOG_OPEN :: "Open a file##file_browser"
DIALOG_SAVE :: "Save a file##file_browser"
DIALOG :: DIALOG_OPEN

directory :: proc() -> string {
    return string(state.browser.directory[:state.browser.directory_length])
}

headless :: proc(ctx: ^kit.Context) -> ^kit.HeadlessState {
    return cast(^kit.HeadlessState)ctx.backend.state
}

script: []kit.Step = {
    kit.Wait(4),
    // open a picture: the dialog starts in the folder that is remembered, the filter hides notes.txt
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Open picture...##open_picture") }, "the open picture button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.state == .BROWSING && directory() == "/demo/pictures" }, "the dialog opens in the remembered folder"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.listing.count == 3 }, "a folder, two pictures, and no notes.txt"),
    kit.Capture("files_open"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return findRow(1) }, "the second row of the list"),
    kit.ClickAt(&target),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.state == .OPENED && state.picture_size == 747 && state.texture != kit.TEXTURE_NONE }, "a double click opens player_sheet.png"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.picture_name[:state.picture_name_length]) == "player_sheet.png" }, "the name of the picture"),
    // open a sound: the dialog starts where the picture was, a typed folder takes it to the sounds
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Open sound...##open_sound") }, "the open sound button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return directory() == "/demo/pictures" }, "one folder is remembered for both"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_OPEN, "##path") }, "the path field"),
    kit.ClickAt(&target),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Tap(.A),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Type("/demo/sounds"),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return directory() == "/demo/sounds" && state.browser.listing.count == 2 }, "the typed path shows the sounds"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_OPEN, "##name") }, "the name field"),
    kit.ClickAt(&target),
    kit.Type("button_sound.wav"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_OPEN, "Open##choose") }, "the open button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.sound != kit.SOUND_NONE && state.sound_size == 4732 }, "the typed name opens the sound"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Play sound##play") }, "the play button"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return headless(ctx).sounds_played == 1 && state.plays == 1 }, "the button plays the sound"),
    kit.Capture("files_loaded"),
    kit.Wait(2),
    // change the picture and save it into its own folder: open and save remember separately
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Invert picture##invert") }, "the invert button"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.picture_name[:state.picture_name_length]) == "player_sheet_inverted.png" && state.texture != kit.TEXTURE_NONE }, "the picture was inverted and encoded again"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Open and save start in the same folder##same") }, "the folder switch"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.memory == .SEPARATE }, "the switch separates the folders"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Save picture as...##save_picture") }, "the save picture button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.mode == .SAVE && directory() == "/demo/sounds" }, "a save starts from the folder of the last open"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.browser.file_name[:state.browser.file_name_length]) == "player_sheet_inverted.png" }, "the name is suggested"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_SAVE, "##path") }, "the path field of the save dialog"),
    kit.ClickAt(&target),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Tap(.A),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Type("/demo/saved"),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_SAVE, "Save##choose") }, "the save button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        data, found := fb.MemoryFsGet(&state.fs, "/demo/saved/player_sheet_inverted.png")
        return state.browser.state == .SAVED && found && len(data) == state.picture_size
    }, "the picture is in the saved folder"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        open, save := fb.FileBrowserDirectories(&state.browser)
        return open == "/demo/sounds" && save == "/demo/saved"
    }, "the open folder did not move, the save folder did"),
    // the sound: a save starts in the saved folder, a second save of the same name asks before it replaces
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Save sound as...##save_sound") }, "the save sound button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return directory() == "/demo/saved" }, "a save starts where the last save went"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_SAVE, "Save##choose") }, "the save button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { _, found := fb.MemoryFsGet(&state.fs, "/demo/saved/button_sound.wav"); return found }, "the sound is saved"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Save sound as...##save_sound") }, "the save sound button again"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_SAVE, "Save##choose") }, "the save button again"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.confirm && state.browser.state == .BROWSING }, "an existing name asks first"),
    kit.Capture("files_replace"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_SAVE, "Keep it##keep") }, "the keep button"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.browser.confirm && state.browser.state == .BROWSING }, "keeping the file goes back to the dialog"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_SAVE, "Cancel##cancel") }, "the cancel button"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.state == .CANCELLED }, "cancel closes the dialog"),
    // a name that is not there: the dialog stays open and the label says why
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("files", "Open picture...##open_picture") }, "the open picture button"),
    kit.ClickAt(&target),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(DIALOG_OPEN, "##name") }, "the name field"),
    kit.ClickAt(&target),
    kit.Type("missing.png"),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.error == .NOT_FOUND && state.browser.state == .BROWSING }, "a missing file is an error and the dialog stays"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return error_text() == "Error: missing.png: not found" }, "the label says which file and why"),
    kit.Capture("files_error"),
    kit.Wait(2),
    kit.Tap(.ESCAPE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.browser.state == .CANCELLED }, "Escape cancels"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
