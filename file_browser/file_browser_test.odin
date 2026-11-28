#+build !js
package file_browser

import "core:fmt"
import "core:os"
import "core:testing"

IMAGES: Filter = {name = "Images", extensions = {"png", ".JPG", "tar.gz"}}
SOUNDS: Filter = {name = "Sounds", extensions = {"wav", "ogg"}}

@(test)
test_filter_matches_extensions_without_regard_to_case_or_dot :: proc(t: ^testing.T) {
    testing.expect(t, FilterMatches(IMAGES, "photo.png"))
    testing.expect(t, FilterMatches(IMAGES, "PHOTO.PNG"))
    testing.expect(t, FilterMatches(IMAGES, "a.jpg"), "the filter wrote .JPG with a dot and capitals")
    testing.expect(t, FilterMatches(IMAGES, "backup.tar.gz"), "a compound extension")
    testing.expect(t, !FilterMatches(IMAGES, "a.gz"))
    testing.expect(t, !FilterMatches(IMAGES, "png"), "a name without a dot has no extension")
    testing.expect(t, !FilterMatches(IMAGES, ".png"), "a hidden file is not an extension")
    testing.expect(t, !FilterMatches(IMAGES, "photo.png.txt"))
    testing.expect(t, !FilterMatches(IMAGES, "xpng"), "the dot is needed")
    testing.expect(t, FilterMatches({}, "anything"), "no extensions: everything")
    testing.expect(t, FilterMatches({extensions = {"*"}}, "anything.at.all"))
}

@(test)
test_filter_accept_text_is_for_the_html_attribute :: proc(t: ^testing.T) {
    buffer: [64]u8
    testing.expect_value(t, FilterAccept(IMAGES, buffer[:]), ".png,.JPG,.tar.gz")
    testing.expect_value(t, FilterAccept({extensions = {"*"}}, buffer[:]), "")
    testing.expect_value(t, FilterAccept({}, buffer[:]), "")
    testing.expect(t, FilterAccept(IMAGES, buffer[:8]) == ".png", "what does not fit is left out")
    both: [2]Filter = {IMAGES, SOUNDS}
    testing.expect_value(t, FiltersAccept(both[:], buffer[:]), ".png,.JPG,.tar.gz,.wav,.ogg")
    all: [2]Filter = {IMAGES, {}}
    testing.expect(t, FiltersAccept(all[:], buffer[:]) == "", "one filter for everything: no limit")
}

@(test)
test_paths_split_and_join :: proc(t: ^testing.T) {
    parent, ok := PathParent("/a/b/c.png")
    testing.expect(t, ok && parent == "/a/b")
    parent, ok = PathParent("/a/b/")
    testing.expect(t, ok && parent == "/a", "a trailing separator is ignored")
    parent, ok = PathParent("/a")
    testing.expect(t, ok && parent == "/")
    _, ok = PathParent("/")
    testing.expect(t, !ok, "the root has no parent")
    parent, ok = PathParent("C:\\Users\\me")
    testing.expect(t, ok && parent == "C:\\Users")
    parent, ok = PathParent("C:\\Users")
    testing.expect(t, ok && parent == "C:\\")
    _, ok = PathParent("C:\\")
    testing.expect(t, !ok)
    _, ok = PathParent("name")
    testing.expect(t, !ok, "a bare name has no parent")

    testing.expect_value(t, PathFileName("/a/b/c.png"), "c.png")
    testing.expect_value(t, PathFileName("C:\\a\\c.png"), "c.png")
    testing.expect_value(t, PathFileName("c.png"), "c.png")
    testing.expect_value(t, PathFileName("/a/b/"), "")
    testing.expect_value(t, PathDirectory("/a/b/c.png"), "/a/b")
    testing.expect_value(t, PathDirectory("/c.png"), "/")
    testing.expect_value(t, PathDirectory("C:\\c.png"), "C:\\")
    testing.expect_value(t, PathDirectory("c.png"), "")
    testing.expect_value(t, PathExtension("a.PNG"), "PNG")
    testing.expect_value(t, PathExtension("/x.y/a"), "")
    testing.expect_value(t, PathExtension(".hidden"), "")
    testing.expect_value(t, PathExtension("a.tar.gz"), "gz")

    buffer: [32]u8
    joined, joined_ok := PathJoin(buffer[:], "/a/b", "c.png")
    testing.expect(t, joined_ok && joined == "/a/b/c.png")
    joined, joined_ok = PathJoin(buffer[:], "/a/b/", "c.png")
    testing.expect(t, joined_ok && joined == "/a/b/c.png", "no double separator")
    joined, joined_ok = PathJoin(buffer[:], "C:\\a", "c.png")
    testing.expect(t, joined_ok && joined == "C:\\a\\c.png", "the separator of the directory")
    joined, joined_ok = PathJoin(buffer[:], "", "c.png")
    testing.expect(t, joined_ok && joined == "c.png")
    _, joined_ok = PathJoin(buffer[:8], "/a/b", "c.png")
    testing.expect(t, !joined_ok, "does not fit")
}

@(test)
test_listing_filters_hides_sorts_and_stops_when_full :: proc(t: ^testing.T) {
    entries: [6]Entry
    names: [64]u8
    listing: Listing
    ListingInit(&listing, entries[:], names[:])
    listing.filter = IMAGES
    testing.expect(t, ListingAdd(&listing, "zebra", true))
    testing.expect(t, ListingAdd(&listing, "b.png", false, 10))
    testing.expect(t, !ListingAdd(&listing, "notes.txt", false), "the filter leaves it out")
    testing.expect(t, !ListingAdd(&listing, ".hidden", true), "hidden")
    testing.expect(t, ListingAdd(&listing, "Alpha", true))
    testing.expect(t, ListingAdd(&listing, "A.PNG", false, 5))
    testing.expect_value(t, listing.skipped, 2)
    ListingSort(&listing)
    order: [4]string = {"Alpha", "zebra", "A.PNG", "b.png"}
    for i in 0 ..< 4 { testing.expect_value(t, listing.entries[i].name, order[i]) }
    testing.expect_value(t, ListingFind(&listing, "b.png"), 3)
    testing.expect_value(t, ListingFind(&listing, "nope"), -1)

    ListingClear(&listing)
    listing.show_hidden = true
    testing.expect(t, ListingAdd(&listing, ".hidden", true))
    // the names buffer is the limit here (64 bytes)
    for _ in 0 ..< 5 { ListingAdd(&listing, "0123456789012345", true) }
    testing.expect(t, listing.truncated, "the rows ran out")
    testing.expect_value(t, listing.count, 4)
}

// ------------------------------------------------------------------------------------------------------------------------
// A real directory

TestDisk :: struct {
    root: string,
    photos: string,
    music: string,
}

@(private = "file")
makeDisk :: proc(t: ^testing.T) -> (disk: TestDisk, ok: bool) {
    root, err := os.make_directory_temp("", "file_browser_test", context.temp_allocator)
    if !testing.expect(t, err == nil, "a temp directory") { return {}, false }
    disk.root = root
    disk.photos = fmt.tprintf("%s%cphotos", root, PATH_SEPARATOR)
    disk.music = fmt.tprintf("%s%cmusic", root, PATH_SEPARATOR)
    testing.expect(t, os.make_directory(disk.photos) == nil)
    testing.expect(t, os.make_directory(disk.music) == nil)
    testing.expect(t, os.write_entire_file(fmt.tprintf("%s%ccat.png", disk.photos, PATH_SEPARATOR), []u8{1, 2, 3, 4, 5}) == nil)
    testing.expect(t, os.write_entire_file(fmt.tprintf("%s%cnotes.txt", disk.photos, PATH_SEPARATOR), []u8{9}) == nil)
    testing.expect(t, os.write_entire_file(fmt.tprintf("%s%csong.wav", disk.music, PATH_SEPARATOR), []u8{7, 7}) == nil)
    return disk, true
}

@(private = "file")
removeDisk :: proc(disk: TestDisk) {
    os.remove_all(disk.root)
}

// A test must never write or read outside of its temp directory: the Choose of a test goes through this
@(private = "file")
chooseInside :: proc(t: ^testing.T, browser: ^FileBrowser, root: string) {
    directory: string = string(browser.directory[:browser.directory_length])
    if !testing.expect(t, len(directory) >= len(root) && directory[:len(root)] == root, "the dialog is inside of the temp directory") { return }
    FileBrowserChoose(browser)
}

@(private = "file")
Rig :: struct {
    browser: FileBrowser,
    entries: [64]Entry,
    names: [2048]u8,
    buffer: [256]u8,
}

@(private = "file")
rigInit :: proc(rig: ^Rig) {
    FileBrowserInit(&rig.browser, IoOs(), rig.entries[:], rig.names[:])
}

@(test)
test_open_lists_filters_and_reads_a_file :: proc(t: ^testing.T) {
    disk, ok := makeDisk(t)
    if !ok { return }
    defer removeDisk(disk)
    rig: ^Rig = new(Rig)
    defer free(rig)
    rigInit(rig)
    browser: ^FileBrowser = &rig.browser
    filters: [1]Filter = {{name = "Images", extensions = {"png"}}}
    FileBrowserSetDirectories(browser, disk.photos, "")
    FileBrowserOpen(browser, rig.buffer[:], filters[:])
    testing.expect_value(t, browser.state, State.BROWSING)
    testing.expect_value(t, string(browser.directory[:browser.directory_length]), disk.photos)
    testing.expect_value(t, browser.listing.count, 1)
    testing.expect_value(t, browser.listing.entries[0].name, "cat.png")
    testing.expect_value(t, browser.listing.entries[0].size, 5)

    FileBrowserSelect(browser, 0)
    testing.expect_value(t, string(browser.file_name[:browser.file_name_length]), "cat.png")
    chooseInside(t, browser, disk.root)
    result: Result = FileBrowserUpdate(browser)
    testing.expect_value(t, result.kind, ResultKind.OPENED)
    testing.expect_value(t, len(result.data), 5)
    testing.expect(t, len(result.data) == 5 && result.data[0] == 1 && result.data[4] == 5)
    testing.expect_value(t, PathFileName(result.path), "cat.png")
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.NONE)
    testing.expect_value(t, browser.state, State.OPENED)
    status: [128]u8
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Opened cat.png (5 bytes)")
}

@(test)
test_errors_keep_the_dialog_open_and_say_what_went_wrong :: proc(t: ^testing.T) {
    disk, ok := makeDisk(t)
    if !ok { return }
    defer removeDisk(disk)
    rig: ^Rig = new(Rig)
    defer free(rig)
    rigInit(rig)
    browser: ^FileBrowser = &rig.browser
    FileBrowserSetDirectories(browser, disk.photos, "")
    status: [160]u8

    small: [3]u8
    FileBrowserOpen(browser, small[:], {})
    FileBrowserSelect(browser, ListingFind(&browser.listing, "cat.png"))
    chooseInside(t, browser, disk.root)
    result: Result = FileBrowserUpdate(browser)
    testing.expect_value(t, result.kind, ResultKind.FAILED)
    testing.expect_value(t, result.error, Error.TOO_BIG)
    testing.expect_value(t, browser.state, State.BROWSING)
    testing.expect(t, len(FileBrowserStatus(browser, status[:])) > 20)
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Choosing a file to open. Error: cat.png: the file is too big for the buffer")

    // nothing typed, a name that cannot be, a file that is not there
    browser.file_name_length = 0
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).error, Error.NAME_EMPTY)
    fmt.bprint(browser.file_name[:], "a?b.png")
    browser.file_name_length = 7
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).error, Error.NAME_INVALID)
    fmt.bprint(browser.file_name[:], "ghost.png")
    browser.file_name_length = 9
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).error, Error.NOT_FOUND)
    testing.expect_value(t, browser.state, State.BROWSING)

    testing.expect(t, !FileBrowserGoTo(browser, fmt.tprintf("%s%cnowhere", disk.root, PATH_SEPARATOR)))
    testing.expect_value(t, browser.error, Error.NOT_FOUND)
    testing.expect(t, string(browser.directory[:browser.directory_length]) == disk.photos, "the old directory stays")
    testing.expect(t, !FileBrowserGoTo(browser, fmt.tprintf("%s%ccat.png", disk.photos, PATH_SEPARATOR)))
    testing.expect_value(t, browser.error, Error.NOT_A_DIRECTORY)
}

@(test)
test_navigation_enters_directories_and_goes_up :: proc(t: ^testing.T) {
    disk, ok := makeDisk(t)
    if !ok { return }
    defer removeDisk(disk)
    rig: ^Rig = new(Rig)
    defer free(rig)
    rigInit(rig)
    browser: ^FileBrowser = &rig.browser
    FileBrowserSetDirectories(browser, disk.root, "")
    FileBrowserOpen(browser, rig.buffer[:], {})
    testing.expect_value(t, browser.listing.count, 2)
    testing.expect(t, browser.listing.entries[0].directory && browser.listing.entries[0].name == "music", "directories first, by name")
    FileBrowserActivate(browser, 1)
    testing.expect_value(t, string(browser.directory[:browser.directory_length]), disk.photos)
    testing.expect_value(t, browser.listing.count, 2)
    testing.expect(t, FileBrowserUp(browser))
    testing.expect_value(t, string(browser.directory[:browser.directory_length]), disk.root)
    // a double click on a file opens it
    FileBrowserActivate(browser, 1)
    FileBrowserActivate(browser, ListingFind(&browser.listing, "notes.txt"))
    result: Result = FileBrowserUpdate(browser)
    testing.expect_value(t, result.kind, ResultKind.OPENED)
    testing.expect_value(t, len(result.data), 1)
    // the filter changes what is listed
    filters: [2]Filter = {{name = "Text", extensions = {"txt"}}, {name = "Images", extensions = {"png"}}}
    FileBrowserSetDirectories(browser, disk.photos, "")
    FileBrowserOpen(browser, rig.buffer[:], filters[:])
    testing.expect_value(t, browser.listing.count, 1)
    testing.expect_value(t, browser.listing.entries[0].name, "notes.txt")
    FileBrowserSetFilter(browser, 1)
    testing.expect_value(t, browser.listing.entries[0].name, "cat.png")
}

@(test)
test_save_adds_the_extension_asks_before_replacing_and_remembers :: proc(t: ^testing.T) {
    disk, ok := makeDisk(t)
    if !ok { return }
    defer removeDisk(disk)
    rig: ^Rig = new(Rig)
    defer free(rig)
    rigInit(rig)
    browser: ^FileBrowser = &rig.browser
    FileBrowserSetDirectories(browser, disk.music, "")
    filters: [1]Filter = {{name = "Sounds", extensions = {"wav"}}}
    data: [4]u8 = {10, 20, 30, 40}
    FileBrowserSave(browser, data[:], "tone", filters[:])
    // a test must never write outside of its temp directory
    if !testing.expect(t, string(browser.directory[:browser.directory_length]) == disk.music, "the dialog starts in the temp directory") { return }
    testing.expect_value(t, browser.mode, Mode.SAVE)
    chooseInside(t, browser, disk.root)
    result: Result = FileBrowserUpdate(browser)
    testing.expect_value(t, result.kind, ResultKind.SAVED)
    testing.expect_value(t, PathFileName(result.path), "tone.wav")
    written, err := os.read_entire_file(fmt.tprintf("%s%ctone.wav", disk.music, PATH_SEPARATOR), context.temp_allocator)
    testing.expect(t, err == nil && len(written) == 4 && written[3] == 40, "the bytes are on the disk")

    // the same name again asks
    FileBrowserSave(browser, data[:2], "tone.wav", filters[:])
    chooseInside(t, browser, disk.root)
    testing.expect(t, browser.confirm, "the file exists")
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.NONE)
    FileBrowserConfirmReplace(browser, false)
    testing.expect(t, !browser.confirm)
    testing.expect_value(t, browser.state, State.BROWSING)
    chooseInside(t, browser, disk.root)
    FileBrowserConfirmReplace(browser, true)
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.SAVED)
    written, err = os.read_entire_file(fmt.tprintf("%s%ctone.wav", disk.music, PATH_SEPARATOR), context.temp_allocator)
    testing.expect(t, err == nil && len(written) == 2, "replaced")
    status: [128]u8
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Saved tone.wav (2 bytes)")

    // cancel
    FileBrowserSave(browser, data[:], "x", filters[:])
    FileBrowserCancel(browser)
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.CANCELLED)
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Cancelled")
}

@(test)
test_the_last_directories_are_shared_or_separate :: proc(t: ^testing.T) {
    disk, ok := makeDisk(t)
    if !ok { return }
    defer removeDisk(disk)
    rig: ^Rig = new(Rig)
    defer free(rig)
    rigInit(rig)
    browser: ^FileBrowser = &rig.browser
    data: [1]u8 = {1}

    // shared (the default): an open in photos makes the save start in photos, and a save elsewhere moves the open
    testing.expect_value(t, browser.memory, DirectoryMemory.SHARED)
    FileBrowserSetDirectories(browser, disk.photos, "")
    FileBrowserOpen(browser, rig.buffer[:], {})
    FileBrowserSelect(browser, ListingFind(&browser.listing, "cat.png"))
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.OPENED)
    open, save := FileBrowserDirectories(browser)
    testing.expect(t, open == disk.photos && save == disk.photos, "both")
    FileBrowserSave(browser, data[:], "copy.png", {})
    testing.expect(t, string(browser.directory[:browser.directory_length]) == disk.photos, "the save starts where the open was")
    FileBrowserGoTo(browser, disk.music)
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.SAVED)
    open, save = FileBrowserDirectories(browser)
    testing.expect(t, open == disk.music && save == disk.music, "a save moves the shared one")
    FileBrowserOpen(browser, rig.buffer[:], {})
    testing.expect_value(t, string(browser.directory[:browser.directory_length]), disk.music)
    FileBrowserCancel(browser)

    // separate: each keeps its own
    FileBrowserSetMemory(browser, .SEPARATE)
    open, save = FileBrowserDirectories(browser)
    testing.expect(t, open == disk.music && save == disk.music, "the save starts from the shared one")
    FileBrowserOpen(browser, rig.buffer[:], {})
    FileBrowserGoTo(browser, disk.photos)
    FileBrowserSelect(browser, ListingFind(&browser.listing, "cat.png"))
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.OPENED)
    open, save = FileBrowserDirectories(browser)
    testing.expect(t, open == disk.photos && save == disk.music, "the open moved, the save did not")
    FileBrowserSave(browser, data[:], "again.png", {})
    testing.expect_value(t, string(browser.directory[:browser.directory_length]), disk.music)
    chooseInside(t, browser, disk.root)
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.SAVED)
    FileBrowserOpen(browser, rig.buffer[:], {})
    testing.expect_value(t, string(browser.directory[:browser.directory_length]), disk.photos)
    FileBrowserCancel(browser)
    // a cancel remembers nothing
    FileBrowserSave(browser, data[:], "no.png", {})
    FileBrowserGoTo(browser, disk.root)
    FileBrowserCancel(browser)
    _, save = FileBrowserDirectories(browser)
    testing.expect_value(t, save, disk.music)
}

@(test)
test_a_remembered_directory_that_is_gone_falls_back_to_a_parent :: proc(t: ^testing.T) {
    disk, ok := makeDisk(t)
    if !ok { return }
    defer removeDisk(disk)
    rig: ^Rig = new(Rig)
    defer free(rig)
    rigInit(rig)
    browser: ^FileBrowser = &rig.browser
    gone: string = fmt.tprintf("%s%cphotos%cold%cdeep", disk.root, PATH_SEPARATOR, PATH_SEPARATOR, PATH_SEPARATOR)
    FileBrowserSetDirectories(browser, gone, "")
    FileBrowserOpen(browser, rig.buffer[:], {})
    testing.expect(t, string(browser.directory[:browser.directory_length]) == disk.photos, "the nearest parent that exists")
    FileBrowserCancel(browser)
    // nothing remembered: the start of the Io
    FileBrowserSetDirectories(browser, "", "")
    FileBrowserOpen(browser, rig.buffer[:], {})
    testing.expect(t, browser.directory_length > 0, "home or the working directory")
    testing.expect_value(t, browser.state, State.BROWSING)
    FileBrowserCancel(browser)
}

// ------------------------------------------------------------------------------------------------------------------------
// The chooser of a browser, faked

@(private = "file")
Fake :: struct {
    accept: [64]u8,
    accept_length: int,
    status: PickStatus,
    name: string,
    bytes: []u8,
    downloaded_name: [64]u8,
    downloaded_length: int,
    downloaded: [16]u8,
    downloaded_count: int,
}

@(private = "file")
fakeIo :: proc(fake: ^Fake) -> Io {
    return {
        user = fake,
        pick_start = proc(user: rawptr, accept: string) {
            fake: ^Fake = cast(^Fake)user
            fake.accept_length = copy(fake.accept[:], accept)
            fake.status = .PENDING
        },
        pick_poll = proc(user: rawptr) -> PickStatus {
            return (cast(^Fake)user).status
        },
        pick_name = proc(user: rawptr, buffer: []u8) -> string {
            fake: ^Fake = cast(^Fake)user
            return string(buffer[:copy(buffer, fake.name)])
        },
        pick_take = proc(user: rawptr, buffer: []u8) -> (count: int, err: Error) {
            fake: ^Fake = cast(^Fake)user
            if len(fake.bytes) > len(buffer) { return 0, .TOO_BIG }
            return copy(buffer, fake.bytes), .NONE
        },
        download = proc(user: rawptr, name: string, data: []u8) -> Error {
            fake: ^Fake = cast(^Fake)user
            fake.downloaded_length = copy(fake.downloaded_name[:], name)
            fake.downloaded_count = copy(fake.downloaded[:], data)
            return .NONE
        },
    }
}

@(test)
test_the_native_chooser_replaces_the_dialog :: proc(t: ^testing.T) {
    fake: Fake
    rig: ^Rig = new(Rig)
    defer free(rig)
    FileBrowserInit(&rig.browser, fakeIo(&fake), rig.entries[:], rig.names[:])
    browser: ^FileBrowser = &rig.browser
    filters: [2]Filter = {IMAGES, SOUNDS}
    FileBrowserOpen(browser, rig.buffer[:], filters[:])
    testing.expect_value(t, browser.state, State.PICKING)
    testing.expect(t, string(fake.accept[:fake.accept_length]) == ".png,.JPG,.tar.gz,.wav,.ogg", "the chooser is told the extensions")
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.NONE)
    status: [128]u8
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Waiting for the file chooser of the browser")

    fake.name = "dog.png"
    fake.bytes = []u8{4, 5, 6}
    fake.status = .READY
    result: Result = FileBrowserUpdate(browser)
    testing.expect_value(t, result.kind, ResultKind.OPENED)
    testing.expect_value(t, result.path, "dog.png")
    testing.expect(t, len(result.data) == 3 && result.data[2] == 6)
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Opened dog.png (3 bytes)")

    // too big for the buffer of the program, and a cancel
    small: [2]u8
    FileBrowserOpen(browser, small[:], {})
    fake.status = .READY
    testing.expect_value(t, FileBrowserUpdate(browser).error, Error.TOO_BIG)
    testing.expect_value(t, browser.state, State.FAILED)
    testing.expect_value(t, FileBrowserStatus(browser, status[:]), "Error: dog.png: the file is too big for the buffer")
    FileBrowserOpen(browser, rig.buffer[:], {})
    fake.status = .CANCELLED
    testing.expect_value(t, FileBrowserUpdate(browser).kind, ResultKind.CANCELLED)

    // a save is a download, at once, and the extension of the filter is added
    data: [3]u8 = {1, 2, 3}
    one: [1]Filter = {{name = "Sounds", extensions = {"wav"}}}
    FileBrowserSave(browser, data[:], "tone", one[:])
    result = FileBrowserUpdate(browser)
    testing.expect_value(t, result.kind, ResultKind.SAVED)
    testing.expect_value(t, string(fake.downloaded_name[:fake.downloaded_length]), "tone.wav")
    testing.expect_value(t, fake.downloaded_count, 3)
}
