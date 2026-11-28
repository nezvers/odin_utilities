package file_browser

import "core:fmt"
import ui "../ui"

// The state of one file chooser: open a file into a buffer of the program, or save the bytes of the program under a name. Two ways to get there, the same for the program:
//   - a desktop program shows a dialog of its own (`UiFileBrowser`, ui_browser.odin) that lists the directories through an `Io`;
//   - a program in a web page cannot see the disk: `Io.pick_start` and the other native procs hand the job to the file chooser of the browser, and a save is a download.
//
//     FileBrowserInit(&fb, IoOs(), entries[:], names[:])            // once, the memory is yours
//     FileBrowserOpen(&fb, buffer, filters)                         // "Open..." was pressed; the file lands in `buffer`
//     result := UiFileBrowser(&ctx, &fb)                            // every frame (draws the dialog); kind OPENED has `data`
//
// What happened is also text for a label (`FileBrowserStatus`): the state of the interaction and the error. The directory of the last open and the last save are remembered, one for both
// or one each (`FileBrowser.memory`), and can be saved with the settings of the program (`FileBrowserDirectories`, `FileBrowserSetDirectories`).
// Limits: one dialog at a time; a file is read whole into the buffer of the program (no streaming, no partial read); a directory of more entries than the Listing holds is cut (`Listing.truncated`);
// names are shown as bytes (UTF-8), sorted by ASCII case folding; no thumbnails, no multi select, no creating folders; the web version cannot choose where it saves (the browser decides) nor remember a directory.

MESSAGE_MAX :: 256

Mode :: enum {
    OPEN,
    SAVE,
}

State :: enum {
    IDLE,                   // nothing asked yet
    BROWSING,               // the dialog is open
    PICKING,                // the chooser of the browser is open
    OPENED,                 // the last request read a file
    SAVED,                  // the last request wrote a file
    CANCELLED,
    FAILED,
}

// Where the dialog starts. SHARED: the folder of the last open or save, either. SEPARATE: the folder of the last open for an open and the folder of the last save for a save.
DirectoryMemory :: enum {
    SHARED,
    SEPARATE,
}

ResultKind :: enum {
    NONE,                   // nothing happened in this call
    OPENED,                 // `data` are the bytes, `path` the file
    SAVED,
    CANCELLED,
    FAILED,                 // `error`; in the dialog it stays open and shows the message, a native chooser is done
}

// What one call of `FileBrowserUpdate` found. The strings and `data` are views of memory of the browser or of the program: valid until the next request.
Result :: struct {
    kind: ResultKind,
    path: string,
    data: []u8,
    error: Error,
}

FileBrowser :: struct {
    io: Io,
    state: State,
    mode: Mode,
    memory: DirectoryMemory,
    replace_ask: bool,                  // a save over a file that exists asks first (default true)
    show_hidden: bool,
    filters: []Filter,
    filter_index: int,

    directory: [PATH_MAX]u8,            // the directory that is shown
    directory_length: int,
    edit: [PATH_MAX]u8,                 // the text of the path field of the dialog
    edit_length: int,
    file_name: [NAME_MAX]u8,            // the text of the name field
    file_name_length: int,
    path: [PATH_MAX]u8,                 // the file of the last open or save
    path_length: int,
    open_directory: [PATH_MAX]u8,       // remembered
    open_directory_length: int,
    save_directory: [PATH_MAX]u8,
    save_directory_length: int,

    listing: Listing,
    list: ui.VirtualList,
    confirm: bool,                      // the replace question is open

    destination: []u8,                  // OPEN: where the bytes go
    source: []u8,                       // SAVE: what is written
    transferred: int,                   // bytes of the last open or save

    message: [MESSAGE_MAX]u8,           // what went wrong, with the name
    message_length: int,
    error: Error,
    event: Result,                      // handed out once by FileBrowserUpdate
}

// `entries` and `names` are the memory of the listing of one directory (a few hundred entries and about 32 bytes of name each is plenty for a dialog).
FileBrowserInit :: proc(browser: ^FileBrowser, io: Io, entries: []Entry, names: []u8) {
    browser^ = {io = io, replace_ask = true}
    browser.list = {selected = ui.VIRTUAL_NONE}
    ListingInit(&browser.listing, entries, names)
}

// ------------------------------------------------------------------------------------------------------------------------
// Requests

// Choose a file to read into `destination`. The result arrives from `FileBrowserUpdate` (the dialog calls it every frame).
FileBrowserOpen :: proc(browser: ^FileBrowser, destination: []u8, filters: []Filter = {}) {
    start(browser, .OPEN, filters)
    browser.destination = destination
    if IoNative(&browser.io) {
        accept: [256]u8
        browser.io.pick_start(browser.io.user, FiltersAccept(filters, accept[:]))
        browser.state = .PICKING
        return
    }
    begin(browser)
}

// Choose a name for `data` and write it there (`data` has to stay as it is until the result is in). On the web the name is only a suggestion for the download and the result comes at once.
FileBrowserSave :: proc(browser: ^FileBrowser, data: []u8, suggested_name: string, filters: []Filter = {}) {
    start(browser, .SAVE, filters)
    browser.source = data
    setFileName(browser, suggested_name)
    if IoNative(&browser.io) {
        name: string = withExtension(browser, string(browser.file_name[:browser.file_name_length]))
        if err := browser.io.download(browser.io.user, name, data); err != .NONE {
            fail(browser, err, name)
            browser.state = .FAILED
        } else {
            browser.transferred = len(data)
            copyPath(browser, name)
            finish(browser, .SAVED)
        }
        return
    }
    begin(browser)
}

// Close the dialog without a result (the Cancel button and Escape do it)
FileBrowserCancel :: proc(browser: ^FileBrowser) {
    if browser.state != .BROWSING { return }
    browser.confirm = false
    browser.error = .NONE
    browser.message_length = 0
    browser.state = .CANCELLED
    browser.event = {kind = .CANCELLED}
}

// Call once a frame: reads the answer of a native chooser and hands out the result of the request, once.
FileBrowserUpdate :: proc(browser: ^FileBrowser) -> Result {
    if browser.state == .PICKING { poll(browser) }
    result: Result = browser.event
    browser.event = {}
    return result
}

// ------------------------------------------------------------------------------------------------------------------------
// The dialog's moves (the ui calls these, a program can too: a test does)

// Show another directory. False (and `error` set, the old directory stays) when it is not one.
FileBrowserGoTo :: proc(browser: ^FileBrowser, directory: string) -> bool {
    exists, is_directory := browser.io.stat(browser.io.user, directory)
    if !exists {
        fail(browser, .NOT_FOUND, directory)
        return false
    }
    if !is_directory {
        fail(browser, .NOT_A_DIRECTORY, directory)
        return false
    }
    if len(directory) > len(browser.directory) {
        fail(browser, .NAME_INVALID, "the path is too long")
        return false
    }
    copy(browser.directory[:], directory)
    browser.directory_length = len(directory)
    return refresh(browser)
}

// The listing of the shown directory again (a filter or the hidden switch changed)
FileBrowserRefresh :: proc(browser: ^FileBrowser) -> bool {
    return refresh(browser)
}

FileBrowserUp :: proc(browser: ^FileBrowser) -> bool {
    parent, ok := PathParent(string(browser.directory[:browser.directory_length]))
    if !ok { return false }
    return FileBrowserGoTo(browser, parent)
}

FileBrowserSetFilter :: proc(browser: ^FileBrowser, index: int) {
    if len(browser.filters) == 0 { return }
    browser.filter_index = clamp(index, 0, len(browser.filters) - 1)
    refresh(browser)
}

// A click on a row: a file gives its name to the name field
FileBrowserSelect :: proc(browser: ^FileBrowser, row: int) {
    if row < 0 || row >= browser.listing.count { return }
    browser.list.selected = row
    if !browser.listing.entries[row].directory { setFileName(browser, browser.listing.entries[row].name) }
}

// A double click or Enter on a row: a directory is entered, a file is chosen
FileBrowserActivate :: proc(browser: ^FileBrowser, row: int) {
    if row < 0 || row >= browser.listing.count { return }
    entry: Entry = browser.listing.entries[row]
    if entry.directory {
        path: [PATH_MAX]u8
        joined, ok := PathJoin(path[:], string(browser.directory[:browser.directory_length]), entry.name)
        if ok { FileBrowserGoTo(browser, joined) } else { fail(browser, .NAME_INVALID, entry.name) }
        return
    }
    setFileName(browser, entry.name)
    FileBrowserChoose(browser)
}

// The Open or Save button: act on the name in the name field. The result comes from FileBrowserUpdate.
FileBrowserChoose :: proc(browser: ^FileBrowser) {
    browser.error = .NONE
    browser.message_length = 0
    name: string = string(browser.file_name[:browser.file_name_length])
    if len(name) == 0 {
        fail(browser, .NAME_EMPTY, "")
        return
    }
    for c in transmute([]u8)name {
        if PathIsSeparator(c) || c < 32 || c == '<' || c == '>' || c == ':' || c == '"' || c == '|' || c == '?' || c == '*' {
            fail(browser, .NAME_INVALID, name)
            return
        }
    }
    if browser.mode == .SAVE { name = withExtension(browser, name) }
    path: [PATH_MAX]u8
    joined, ok := PathJoin(path[:], string(browser.directory[:browser.directory_length]), name)
    if !ok {
        fail(browser, .NAME_INVALID, name)
        return
    }
    exists, is_directory := browser.io.stat(browser.io.user, joined)
    if is_directory {
        // a name that is a directory enters it
        browser.file_name_length = 0
        FileBrowserGoTo(browser, joined)
        return
    }
    switch browser.mode {
    case .OPEN:
        if !exists {
            fail(browser, .NOT_FOUND, name)
            return
        }
        count, err := browser.io.read(browser.io.user, joined, browser.destination)
        if err != .NONE {
            fail(browser, err, name)
            return
        }
        browser.transferred = count
        copyPath(browser, joined)
        rememberDirectory(browser)
        finish(browser, .OPENED)
    case .SAVE:
        if exists && browser.replace_ask && !browser.confirm {
            browser.confirm = true
            copyPath(browser, joined)
            return
        }
        browser.confirm = false
        if err := browser.io.write(browser.io.user, joined, browser.source); err != .NONE {
            fail(browser, err, name)
            return
        }
        browser.transferred = len(browser.source)
        copyPath(browser, joined)
        rememberDirectory(browser)
        finish(browser, .SAVED)
    }
}

// The answer to "replace it?": yes writes, no goes back to the dialog
FileBrowserConfirmReplace :: proc(browser: ^FileBrowser, yes: bool) {
    if !browser.confirm { return }
    if !yes {
        browser.confirm = false
        return
    }
    FileBrowserChoose(browser)
}

// ------------------------------------------------------------------------------------------------------------------------
// Remembered directories

// The directories that the next open and the next save start in. With `memory` SHARED both are the same.
FileBrowserDirectories :: proc(browser: ^FileBrowser) -> (open: string, save: string) {
    open = string(browser.open_directory[:browser.open_directory_length])
    if browser.memory == .SHARED { return open, open }
    return open, string(browser.save_directory[:browser.save_directory_length])
}

// Put the directories back that a program saved with its settings. A directory that does not exist (any more) is not an error: the dialog falls back to a parent of it.
FileBrowserSetDirectories :: proc(browser: ^FileBrowser, open: string, save: string) {
    browser.open_directory_length = copyText(browser.open_directory[:], open)
    browser.save_directory_length = copyText(browser.save_directory[:], save)
}

// Same folder for open and save, or one each. Going to SEPARATE gives the save its own start from the shared one.
FileBrowserSetMemory :: proc(browser: ^FileBrowser, memory: DirectoryMemory) {
    if memory == .SEPARATE && browser.memory == .SHARED {
        browser.save_directory_length = copyText(browser.save_directory[:], string(browser.open_directory[:browser.open_directory_length]))
    }
    browser.memory = memory
}

// ------------------------------------------------------------------------------------------------------------------------
// The text for a label

// One line for a label: what the chooser is doing, what it did last, or the error. Written into `buffer`.
FileBrowserStatus :: proc(browser: ^FileBrowser, buffer: []u8) -> string {
    name: string = PathFileName(string(browser.path[:browser.path_length]))
    switch browser.state {
    case .IDLE: return fmt.bprintf(buffer, "Idle")
    case .BROWSING:
        what: string = "open" if browser.mode == .OPEN else "save"
        if browser.error != .NONE { return fmt.bprintf(buffer, "Choosing a file to %s. Error: %s", what, string(browser.message[:browser.message_length])) }
        return fmt.bprintf(buffer, "Choosing a file to %s in %s", what, string(browser.directory[:browser.directory_length]))
    case .PICKING: return fmt.bprintf(buffer, "Waiting for the file chooser of the browser")
    case .OPENED: return fmt.bprintf(buffer, "Opened %s (%d bytes)", name, browser.transferred)
    case .SAVED: return fmt.bprintf(buffer, "Saved %s (%d bytes)", name, browser.transferred)
    case .CANCELLED: return fmt.bprintf(buffer, "Cancelled")
    case .FAILED: return fmt.bprintf(buffer, "Error: %s", string(browser.message[:browser.message_length]))
    }
    return ""
}

// ------------------------------------------------------------------------------------------------------------------------

@(private)
start :: proc(browser: ^FileBrowser, mode: Mode, filters: []Filter) {
    browser.mode = mode
    browser.filters = filters
    browser.filter_index = 0
    browser.error = .NONE
    browser.message_length = 0
    browser.confirm = false
    browser.event = {}
    browser.file_name_length = 0
    browser.destination, browser.source = nil, nil
}

// The dialog opens in the remembered directory; one that is gone is replaced by the nearest parent that exists, then by the start of the Io
@(private)
begin :: proc(browser: ^FileBrowser) {
    browser.state = .BROWSING
    browser.list.selected = ui.VIRTUAL_NONE
    remembered: string = string(browser.open_directory[:browser.open_directory_length])
    if browser.memory == .SEPARATE && browser.mode == .SAVE { remembered = string(browser.save_directory[:browser.save_directory_length]) }
    directory: string = remembered
    for len(directory) > 0 {
        if exists, is_directory := browser.io.stat(browser.io.user, directory); exists && is_directory { break }
        parent, ok := PathParent(directory)
        if !ok { directory = "" } else { directory = parent }
    }
    fallback: [PATH_MAX]u8
    if len(directory) == 0 { directory = browser.io.start(browser.io.user, fallback[:]) }
    FileBrowserGoTo(browser, directory)
}

@(private)
refresh :: proc(browser: ^FileBrowser) -> bool {
    browser.listing.filter = browser.filters[browser.filter_index] if len(browser.filters) > 0 else {}
    browser.listing.show_hidden = browser.show_hidden
    ListingClear(&browser.listing)
    browser.list.selected = ui.VIRTUAL_NONE
    browser.edit_length = copyText(browser.edit[:], string(browser.directory[:browser.directory_length]))
    err: Error = browser.io.list(browser.io.user, string(browser.directory[:browser.directory_length]), &browser.listing)
    ListingSort(&browser.listing)
    if err != .NONE {
        fail(browser, err, string(browser.directory[:browser.directory_length]))
        return false
    }
    // a name that is typed or suggested is selected when the directory has it
    if row: int = ListingFind(&browser.listing, string(browser.file_name[:browser.file_name_length])); row >= 0 { browser.list.selected = row }
    return true
}

@(private)
poll :: proc(browser: ^FileBrowser) {
    switch browser.io.pick_poll(browser.io.user) {
    case .PENDING: return
    case .CANCELLED:
        browser.state = .CANCELLED
        browser.event = {kind = .CANCELLED}
    case .FAILED:
        fail(browser, .FAILED, "the file chooser")
        browser.state = .FAILED
    case .READY:
        name_buffer: [NAME_MAX]u8
        name: string = browser.io.pick_name(browser.io.user, name_buffer[:])
        count, err := browser.io.pick_take(browser.io.user, browser.destination)
        if err != .NONE {
            fail(browser, err, name)
            browser.state = .FAILED
            return
        }
        browser.transferred = count
        copyPath(browser, name)
        finish(browser, .OPENED)
    }
}

@(private)
finish :: proc(browser: ^FileBrowser, kind: ResultKind) {
    browser.error = .NONE
    browser.message_length = 0
    browser.confirm = false
    result: Result = {kind = kind, path = string(browser.path[:browser.path_length])}
    if kind == .OPENED {
        browser.state = .OPENED
        result.data = browser.destination[:browser.transferred]
    } else {
        browser.state = .SAVED
    }
    browser.event = result
}

// An error: the message names what it was about. The dialog stays open (state is not changed here).
@(private)
fail :: proc(browser: ^FileBrowser, error: Error, subject: string) {
    browser.error = error
    text: string
    if len(subject) > 0 {
        text = fmt.bprintf(browser.message[:], "%s: %s", subject, ErrorText(error))
    } else {
        text = fmt.bprintf(browser.message[:], "%s", ErrorText(error))
    }
    browser.message_length = len(text)
    browser.event = {kind = .FAILED, error = error}
}

@(private)
copyText :: proc(destination: []u8, text: string) -> int {
    count: int = min(len(text), len(destination))
    copy(destination, text[:count])
    return count
}

@(private)
copyPath :: proc(browser: ^FileBrowser, path: string) {
    browser.path_length = copyText(browser.path[:], path)
}

@(private)
setFileName :: proc(browser: ^FileBrowser, name: string) {
    browser.file_name_length = copyText(browser.file_name[:], name)
}

// the directory of the file just opened or saved becomes the next start
@(private)
rememberDirectory :: proc(browser: ^FileBrowser) {
    directory: string = PathDirectory(string(browser.path[:browser.path_length]))
    if len(directory) == 0 { return }
    if browser.mode == .SAVE && browser.memory == .SEPARATE {
        browser.save_directory_length = copyText(browser.save_directory[:], directory)
    } else {
        browser.open_directory_length = copyText(browser.open_directory[:], directory)
    }
}

// A name without an extension gets the one of the filter, when the filter has exactly one
@(private)
withExtension :: proc(browser: ^FileBrowser, name: string) -> string {
    if len(PathExtension(name)) > 0 || len(browser.filters) == 0 { return name }
    filter: Filter = browser.filters[browser.filter_index]
    if len(filter.extensions) != 1 { return name }
    extension: string = filter.extensions[0]
    if len(extension) > 0 && extension[0] == '.' { extension = extension[1:] }
    if len(extension) == 0 || extension == "*" { return name }
    // written behind the name in its own field: the name field is the only place it can live without an allocation
    if browser.file_name_length + 1 + len(extension) > len(browser.file_name) { return name }
    if string(browser.file_name[:browser.file_name_length]) != name { return name }
    browser.file_name[browser.file_name_length] = '.'
    copy(browser.file_name[browser.file_name_length + 1:], extension)
    browser.file_name_length += 1 + len(extension)
    return string(browser.file_name[:browser.file_name_length])
}
