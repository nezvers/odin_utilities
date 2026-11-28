#+build !js
package file_browser

import "core:testing"

@(private = "file")
Memory :: struct {
    fs: MemoryFs,
    files: [16]MemoryFile,
    storage: [256]u8,
}

@(private = "file")
memoryInit :: proc(memory: ^Memory) {
    MemoryFsInit(&memory.fs, memory.files[:], memory.storage[:])
}

@(test)
test_memory_fs_lists_stats_reads_and_writes :: proc(t: ^testing.T) {
    memory: ^Memory = new(Memory)
    defer free(memory)
    memoryInit(memory)
    fs: ^MemoryFs = &memory.fs
    testing.expect_value(t, MemoryFsAdd(fs, "/pictures/cat.png", []u8{1, 2, 3}), Error.NONE)
    testing.expect_value(t, MemoryFsAdd(fs, "/pictures/old/dog.png", []u8{4}), Error.NONE)
    testing.expect_value(t, MemoryFsAdd(fs, "/sounds/tone.wav", []u8{5, 6}), Error.NONE)
    testing.expect_value(t, MemoryFsAdd(fs, "/readme.txt", []u8{7}), Error.NONE)
    testing.expect_value(t, MemoryFsDirectory(fs, "/empty"), Error.NONE)
    io: Io = IoMemory(fs)

    exists, directory := io.stat(fs, "/pictures")
    testing.expect(t, exists && directory, "a directory is the prefix of a file")
    exists, directory = io.stat(fs, "/pictures/cat.png")
    testing.expect(t, exists && !directory)
    exists, directory = io.stat(fs, "/empty")
    testing.expect(t, exists && directory)
    exists, _ = io.stat(fs, "/nothing")
    testing.expect(t, !exists)
    exists, directory = io.stat(fs, "/")
    testing.expect(t, exists && directory)
    exists, _ = io.stat(fs, "/pict")
    testing.expect(t, !exists, "a prefix of a name is not a directory")

    entries: [16]Entry
    names: [256]u8
    listing: Listing
    ListingInit(&listing, entries[:], names[:])
    testing.expect_value(t, io.list(fs, "/", &listing), Error.NONE)
    ListingSort(&listing)
    testing.expect_value(t, listing.count, 4)
    order: [4]string = {"empty", "pictures", "sounds", "readme.txt"}
    for i in 0 ..< 4 { testing.expect_value(t, listing.entries[i].name, order[i]) }
    ListingClear(&listing)
    testing.expect_value(t, io.list(fs, "/pictures", &listing), Error.NONE)
    ListingSort(&listing)
    testing.expect_value(t, listing.count, 2)
    testing.expect(t, listing.entries[0].name == "old" && listing.entries[0].directory)
    testing.expect(t, listing.entries[1].name == "cat.png" && listing.entries[1].size == 3)
    testing.expect_value(t, io.list(fs, "/pictures/cat.png", &listing), Error.NOT_A_DIRECTORY)
    testing.expect_value(t, io.list(fs, "/nothing", &listing), Error.NOT_FOUND)

    buffer: [8]u8
    count, err := io.read(fs, "/pictures/cat.png", buffer[:])
    testing.expect(t, err == .NONE && count == 3 && buffer[2] == 3)
    _, err = io.read(fs, "/pictures/cat.png", buffer[:2])
    testing.expect_value(t, err, Error.TOO_BIG)
    _, err = io.read(fs, "/nothing", buffer[:])
    testing.expect_value(t, err, Error.NOT_FOUND)
    _, err = io.read(fs, "/empty", buffer[:])
    testing.expect_value(t, err, Error.IS_A_DIRECTORY)

    // a write replaces
    testing.expect_value(t, io.write(fs, "/pictures/cat.png", []u8{9, 9}), Error.NONE)
    data, found := MemoryFsGet(fs, "/pictures/cat.png")
    testing.expect(t, found && len(data) == 2 && data[0] == 9)
    testing.expect_value(t, io.write(fs, "/pictures", []u8{1}), Error.IS_A_DIRECTORY)
}

@(test)
test_memory_fs_fails_when_full_and_the_browser_works_on_it :: proc(t: ^testing.T) {
    memory: ^Memory = new(Memory)
    defer free(memory)
    MemoryFsInit(&memory.fs, memory.files[:2], memory.storage[:8])
    fs: ^MemoryFs = &memory.fs
    testing.expect_value(t, MemoryFsAdd(fs, "/a.png", []u8{1, 2, 3, 4, 5}), Error.NONE)
    testing.expect(t, MemoryFsAdd(fs, "/b.png", []u8{1, 2, 3, 4}) == .FAILED, "the storage is full")
    testing.expect_value(t, MemoryFsAdd(fs, "/c.png", []u8{1}), Error.NONE)
    testing.expect(t, MemoryFsAdd(fs, "/d.png", []u8{1}) == .FAILED, "the file table is full")

    // the browser over it: the whole flow without a disk
    memory2: ^Memory = new(Memory)
    defer free(memory2)
    memoryInit(memory2)
    MemoryFsAdd(&memory2.fs, "/pictures/cat.png", []u8{1, 2, 3})
    MemoryFsAdd(&memory2.fs, "/pictures/notes.txt", []u8{1})
    entries: [16]Entry
    names: [256]u8
    browser: FileBrowser
    FileBrowserInit(&browser, IoMemory(&memory2.fs), entries[:], names[:])
    FileBrowserSetDirectories(&browser, "/pictures", "")
    buffer: [16]u8
    filters: [1]Filter = {{name = "Pictures", extensions = {"png"}}}
    FileBrowserOpen(&browser, buffer[:], filters[:])
    testing.expect_value(t, browser.listing.count, 1)
    FileBrowserActivate(&browser, 0)
    result: Result = FileBrowserUpdate(&browser)
    testing.expect_value(t, result.kind, ResultKind.OPENED)
    testing.expect_value(t, len(result.data), 3)
    testing.expect_value(t, result.path, "/pictures/cat.png")
}
