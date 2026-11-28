package file_browser

import "core:fmt"
import ui "../ui"

// The dialog of a FileBrowser, drawn with the ui library: a modal with the directory (a field you can type in, and an Up button), the files of the directory (directories first), a filter dropdown when
// there is more than one filter, the name field, the buttons and the error. Where the platform has its own chooser (a web page) nothing is drawn: the call only reads the answer of the browser.
//
//     result := file_browser.UiFileBrowser(&ctx, &browser)         // once per frame, anywhere between UiBegin and UiEnd
//     #partial switch result.kind { case .OPENED: use(result.data) ... }
//
// Ids: the modal is `<title>##<name>`, its parts are `##path`, `##up`, `##files`, `##filter`, `##name`, `##choose`, `##cancel`, `##replace`, `##keep` under it. The rows are of `FILE_ROW_HEIGHT`.
// Limits: the dialog is a fixed size (`DIALOG_WIDTH` x `DIALOG_HEIGHT`) and does not resize or move; at most `MAX_FILTERS` filters in the dropdown; rows show a name and a size (no dates, no icons per type).

DIALOG_WIDTH :: 600
DIALOG_HEIGHT :: 460
FILE_ROW_HEIGHT :: 26
MAX_FILTERS :: 16

UiFileBrowser :: proc(ctx: ^ui.Context, browser: ^FileBrowser, name: string = "file_browser") -> Result {
    if browser.state == .BROWSING && !IoNative(&browser.io) {
        open: bool = true
        title: string = fmt.tprintf("%s##%s", "Open a file" if browser.mode == .OPEN else "Save a file", name)
        if ui.UiModal(ctx, title, &open, {ui.Fixed(DIALOG_WIDTH), ui.Fixed(DIALOG_HEIGHT)}) {
            ui.UiTitle(ctx, "Open a file" if browser.mode == .OPEN else "Save a file")
            drawDirectory(ctx, browser)
            drawFiles(ctx, browser)
            drawFilters(ctx, browser)
            drawName(ctx, browser)
            drawButtons(ctx, browser)
        }
        // Escape (or whatever closes a modal) cancels
        if !open { FileBrowserCancel(browser) }
    }
    return FileBrowserUpdate(browser)
}

@(private)
drawDirectory :: proc(ctx: ^ui.Context, browser: ^FileBrowser) {
    if ui.UiRow(ctx, {gap = 8, size = {ui.Grow(), {}}}) {
        _, can_go_up := PathParent(string(browser.directory[:browser.directory_length]))
        if ui.UiButton(ctx, "##up", {}, !can_go_up, .CHEVRON_UP) { FileBrowserUp(browser) }
        _, submitted := ui.UiTextField(ctx, "##path", browser.edit[:], &browser.edit_length, {ui.Grow(), {}})
        if submitted { FileBrowserGoTo(browser, string(browser.edit[:browser.edit_length])) }
    }
}

@(private)
drawFiles :: proc(ctx: ^ui.Context, browser: ^FileBrowser) {
    list: ^ui.VirtualList = &browser.list
    listing: ^Listing = &browser.listing
    if ui.UiVirtual(ctx, "##files", list, listing.count, FILE_ROW_HEIGHT, {ui.Grow(), ui.Grow()}) {
        for row in list.first ..< list.last {
            entry: Entry = listing.entries[row]
            if ui.UiVirtualRow(ctx, list, row) {
                ui.UiIcon(ctx, .FOLDER if entry.directory else .FILE, 16)
                ui.UiLabel(ctx, entry.name)
                ui.UiSpacer(ctx)
                if !entry.directory {
                    size: [24]u8
                    ui.UiLabelDim(ctx, SizeText(entry.size, size[:]))
                }
            }
        }
    }
    if list.changed { FileBrowserSelect(browser, list.selected) }
    if list.activated { FileBrowserActivate(browser, list.selected) }
    if listing.truncated {
        ui.UiLabelDim(ctx, "Only the first entries of this directory are shown.")
    }
}

@(private)
drawFilters :: proc(ctx: ^ui.Context, browser: ^FileBrowser) {
    if len(browser.filters) < 2 { return }
    names: [MAX_FILTERS]string
    count: int = min(len(browser.filters), MAX_FILTERS)
    for i in 0 ..< count { names[i] = browser.filters[i].name }
    selected: int = browser.filter_index
    if ui.UiDropdown(ctx, "##filter", names[:count], &selected, {ui.Grow(), {}}) { FileBrowserSetFilter(browser, selected) }
}

@(private)
drawName :: proc(ctx: ^ui.Context, browser: ^FileBrowser) {
    if ui.UiRow(ctx, {gap = 8, size = {ui.Grow(), {}}}) {
        ui.UiLabel(ctx, "Name")
        _, submitted := ui.UiTextField(ctx, "##name", browser.file_name[:], &browser.file_name_length, {ui.Grow(), {}})
        if submitted { FileBrowserChoose(browser) }
    }
}

@(private)
drawButtons :: proc(ctx: ^ui.Context, browser: ^FileBrowser) {
    if browser.error != .NONE && !browser.confirm {
        if ui.UiTagged(ctx, "danger") { ui.UiLabel(ctx, string(browser.message[:browser.message_length]), .WORDS) }
    }
    if browser.confirm {
        ui.UiLabel(ctx, fmt.tprintf("%s exists. Replace it?", PathFileName(string(browser.path[:browser.path_length]))), .WORDS)
        if ui.UiRow(ctx, {gap = 8, size = {ui.Grow(), {}}}) {
            ui.UiSpacer(ctx)
            if ui.UiTagged(ctx, "danger") {
                if ui.UiButton(ctx, "Replace##replace") { FileBrowserConfirmReplace(browser, true) }
            }
            if ui.UiButton(ctx, "Keep it##keep") { FileBrowserConfirmReplace(browser, false) }
        }
        return
    }
    if ui.UiRow(ctx, {gap = 8, size = {ui.Grow(), {}}}) {
        ui.UiSpacer(ctx)
        if ui.UiButton(ctx, "Open##choose" if browser.mode == .OPEN else "Save##choose") { FileBrowserChoose(browser) }
        if ui.UiTagged(ctx, "outline") {
            if ui.UiButton(ctx, "Cancel##cancel") { FileBrowserCancel(browser) }
        }
    }
}

// 12 B, 3.4 KB, 1.2 MB: for the rows
SizeText :: proc(size: i64, buffer: []u8) -> string {
    if size < 1024 { return fmt.bprintf(buffer, "%d B", size) }
    if size < 1024 * 1024 { return fmt.bprintf(buffer, "%.1f KB", f64(size) / 1024) }
    if size < 1024 * 1024 * 1024 { return fmt.bprintf(buffer, "%.1f MB", f64(size) / (1024 * 1024)) }
    return fmt.bprintf(buffer, "%.1f GB", f64(size) / (1024 * 1024 * 1024))
}
