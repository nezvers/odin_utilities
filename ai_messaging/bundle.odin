#+build !js
// A folder as one stream of bytes, so it travels through the same chunk / credit / sha256 machinery as a single file and arrives
// all or nothing: the receiver builds it in a staging folder and renames it when the hash matched.
//
// The stream is a sequence of records, then an end mark:
//   [kind u8: 1 file, 2 folder][path length u16][path, '/' separated, relative][flags u8: 1 executable][size u64]  + `size` bytes for a file
//   [0 u8]
// Folders come before what is inside them (the scan is breadth first). Symbolic links are skipped, not followed.
//
// BundleScan / BundleRead (sender) and BundleFeed (receiver) are plain state machines over caller buffers and know nothing about the
// network, so they are tested on their own: any chunking of the stream gives the same folder.
// What a hostile sender can do is limited here: every path component is cleaned (no "..", no absolute paths, no names Windows
// refuses), depth, path length and file count are capped, a record that does not fit the stream ends the transfer.
package ai_messaging

import "base:runtime"
import "core:crypto/sha2"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

BUNDLE_MAX_FILES :: 20000
BUNDLE_PATH_MAX :: 240
BUNDLE_DEPTH_MAX :: 24
BUNDLE_HEADER_MAX :: 1 + 2 + BUNDLE_PATH_MAX + 1 + 8

BundleEntry :: struct {
    path: string,                        // relative, '/' separated, owned by the bundle's allocator
    size: u64,
    directory: bool,
    executable: bool,
}

// ---------------------------------------------------------------------------------------------------------------- sender

Bundle :: struct {
    allocator: runtime.Allocator,
    root: string,                        // the folder being sent (owned)
    entries: [dynamic]BundleEntry,
    total: u64,                          // bytes of the whole stream
    files: int,
    // reading state
    index: int,
    state: BundleState,
    header: [BUNDLE_HEADER_MAX]byte,
    header_length: int,
    header_done: int,
    file: ^os.File,
    data_left: u64,
}

BundleState :: enum {
    HEADER,
    DATA,
    END,
    DONE,
}

@(private)
Slashes :: proc(path: string) -> string {
    result, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
    return result
}

// Does a name match one of the exclusions? "name" matches exactly, "*.ext" matches by ending.
BundleExcluded :: proc(name: string, excludes: []string) -> bool {
    for pattern in excludes {
        if strings.has_prefix(pattern, "*") {
            if strings.has_suffix(name, pattern[1:]) {
                return true
            }
        } else if name == pattern {
            return true
        }
    }
    return false
}

BundleHeaderWrite :: proc(entry: BundleEntry, buffer: []byte) -> int {
    buffer[0] = 2 if entry.directory else 1
    buffer[1] = u8(len(entry.path))
    buffer[2] = u8(len(entry.path) >> 8)
    copy(buffer[3:], entry.path)
    at: int = 3 + len(entry.path)
    buffer[at] = 1 if entry.executable else 0
    for i in 0 ..< 8 {
        buffer[at + 1 + i] = u8(entry.size >> uint(8 * i))
    }
    return at + 9
}

// Lists the folder (breadth first, no links, nothing excluded) and computes the stream size. False: not a folder, too many files,
// a path too long, or too deep. Allocates the list and the paths from `allocator`; BundleDestroy gives them back.
BundleScan :: proc(bundle: ^Bundle, root: string, excludes: []string, allocator: runtime.Allocator) -> bool {
    bundle^ = {allocator = allocator}
    clean: string = strings.trim_right(root, "/\\")
    if clean == "" || !os.is_dir(clean) {
        return false
    }
    // the walker reports absolute paths even for a relative start, so everything is measured against the absolute one
    if absolute, error := os.get_absolute_path(clean, context.temp_allocator); error == nil {
        clean = absolute
    }
    bundle.root = strings.clone(clean, allocator)
    bundle.entries = make([dynamic]BundleEntry, allocator)
    walker: os.Walker = os.walker_create(clean)
    defer os.walker_destroy(&walker)
    prefix: string = strings.concatenate({Slashes(clean), "/"}, context.temp_allocator)
    for info in os.walker_walk(&walker) {
        if _, err := os.walker_error(&walker); err != nil {
            continue                                     // a folder that cannot be read is left out
        }
        full: string = Slashes(info.fullpath)
        if !strings.has_prefix(full, prefix) {
            continue
        }
        relative: string = full[len(prefix):]
        skip: bool = info.type == .Symlink
        depth: int = 1
        for i in 0 ..< len(relative) {
            if relative[i] == '/' {
                depth += 1
            }
        }
        // an excluded folder is not entered (".git", "node_modules"), an excluded file is just left out
        if BundleExcluded(info.name, excludes) {
            if info.type == .Directory {
                os.walker_skip_dir(&walker)
            }
            continue
        }
        if skip || info.type != .Regular && info.type != .Directory {
            if info.type == .Directory {
                os.walker_skip_dir(&walker)
            }
            continue
        }
        if len(relative) > BUNDLE_PATH_MAX || depth > BUNDLE_DEPTH_MAX || len(bundle.entries) >= BUNDLE_MAX_FILES {
            BundleDestroy(bundle)
            return false
        }
        entry: BundleEntry = {
            path = strings.clone(relative, allocator),
            size = u64(max(info.size, 0)) if info.type == .Regular else 0,
            directory = info.type == .Directory,
            executable = info.type == .Regular && .Execute_User in info.mode,
        }
        append(&bundle.entries, entry)
        header: [BUNDLE_HEADER_MAX]byte
        bundle.total += u64(BundleHeaderWrite(entry, header[:])) + entry.size
        if !entry.directory {
            bundle.files += 1
        }
    }
    bundle.total += 1                                    // the end mark
    return true
}

BundleDestroy :: proc(bundle: ^Bundle) {
    if bundle.file != nil {
        os.close(bundle.file)
    }
    for entry in bundle.entries {
        delete(entry.path, bundle.allocator)
    }
    delete(bundle.entries)
    delete(bundle.root, bundle.allocator)
    bundle^ = {}
}

// Fills `out` with the next bytes of the stream (full unless the stream ends). -1: a file could not be read or got shorter.
BundleRead :: proc(bundle: ^Bundle, out: []byte) -> int {
    count: int
    for count < len(out) {
        switch bundle.state {
        case .HEADER:
            if bundle.index >= len(bundle.entries) {
                bundle.state = .END
                continue
            }
            if bundle.header_length == 0 {
                bundle.header_length = BundleHeaderWrite(bundle.entries[bundle.index], bundle.header[:])
                bundle.header_done = 0
            }
            taken: int = min(len(out) - count, bundle.header_length - bundle.header_done)
            copy(out[count:count + taken], bundle.header[bundle.header_done:bundle.header_done + taken])
            count += taken
            bundle.header_done += taken
            if bundle.header_done == bundle.header_length {
                bundle.header_length = 0
                entry: BundleEntry = bundle.entries[bundle.index]
                if entry.directory || entry.size == 0 {
                    bundle.index += 1
                } else {
                    path: string = fmt.tprintf("%s/%s", bundle.root, entry.path)
                    file, error := os.open(path)
                    if error != nil {
                        return -1
                    }
                    bundle.file = file
                    bundle.data_left = entry.size
                    bundle.state = .DATA
                }
            }
        case .DATA:
            want: int = int(min(u64(len(out) - count), bundle.data_left))
            read, error := os.read(bundle.file, out[count:count + want])
            if error != nil || read <= 0 {
                return -1                                // the file got shorter while it was sent
            }
            count += read
            bundle.data_left -= u64(read)
            if bundle.data_left == 0 {
                os.close(bundle.file)
                bundle.file = nil
                bundle.index += 1
                bundle.state = .HEADER
            }
        case .END:
            out[count] = 0
            count += 1
            bundle.state = .DONE
        case .DONE:
            return count
        }
    }
    return count
}

// Reads (and hashes) the first `count` bytes of the stream, so that the next BundleRead goes on from there: what a resumed transfer needs
// on the sending side. False when the folder no longer has that many bytes (it changed since).
BundleSkip :: proc(bundle: ^Bundle, count: u64, hash: ^sha2.Context_256) -> bool {
    piece: [16 * 1024]byte
    done: u64
    for done < count {
        want: int = int(min(u64(len(piece)), count - done))
        read: int = BundleRead(bundle, piece[:want])
        if read != want {
            return false
        }
        sha2.update(hash, piece[:want])
        done += u64(want)
    }
    return true
}

// ---------------------------------------------------------------------------------------------------------------- receiver

BundleReader :: struct {
    root: [260]byte,                     // the staging folder everything is written into
    root_length: int,
    keep_executable: bool,               // set the executable bit of files that had it (off by default: received files do not run)
    state: BundleReadState,
    header: [BUNDLE_HEADER_MAX]byte,
    header_length: int,
    header_need: int,
    file: ^os.File,
    data_left: u64,
    files: int,
    entries: int,
    ended: bool,
    failure: string,
    manifest: ^os.File,                  // the headers of the records so far, in order (see BundleReaderResume); nil = not kept
}

BundleReadState :: enum {
    HEADER,
    DATA,
    ENDED,
    FAILED,
}

// A path from the stream turned into a safe relative path (each component cleaned, never ".." or empty). False: refuse the bundle.
BundlePathSafe :: proc(buffer: []byte, wanted: string) -> (path: string, ok: bool) {
    if wanted == "" || len(wanted) > BUNDLE_PATH_MAX || strings.has_prefix(wanted, "/") {
        return
    }
    length: int
    depth: int
    remaining: string = wanted
    for component in strings.split_iterator(&remaining, "/") {
        if component == "" || component == "." || component == ".." || depth >= BUNDLE_DEPTH_MAX {
            return
        }
        name: [FILE_NAME_MAX]byte
        clean: string = FileNameSafe(name[:], component, true)
        if length + len(clean) + 1 > len(buffer) {
            return
        }
        if depth > 0 {
            buffer[length] = '/'
            length += 1
        }
        copy(buffer[length:], clean)
        length += len(clean)
        depth += 1
    }
    return string(buffer[:length]), true
}

// `manifest_path`: a file that gets the header of every record as it is accepted, which lets an interrupted folder be continued later.
BundleReaderInit :: proc(reader: ^BundleReader, root: string, keep_executable: bool, manifest_path: string = "") {
    reader^ = {keep_executable = keep_executable}
    reader.root_length = min(len(root), len(reader.root))
    copy(reader.root[:reader.root_length], root)
    os.make_directory_all(root)
    if manifest_path != "" {
        reader.manifest, _ = os.open(manifest_path, {.Write, .Create, .Trunc})
    }
}

BundleReaderClose :: proc(reader: ^BundleReader) {
    if reader.file != nil {
        os.close(reader.file)
        reader.file = nil
    }
    if reader.manifest != nil {
        os.close(reader.manifest)
        reader.manifest = nil
    }
}

// Picks up an interrupted folder: the staging folder `root` holds what arrived, `manifest_path` the headers of the records in the order they
// came. The prefix of the stream is rebuilt from them (headers, and the bytes of every file as it is on the disk), hashed into `hash`, and the
// reader is left exactly where the stream stopped: after the last whole record, or inside the file that was being written (appending to it).
// `offset` is how many bytes of the stream that is. False (nothing usable, or the folder does not match the manifest): start over.
BundleReaderResume :: proc(reader: ^BundleReader, root: string, keep_executable: bool, manifest_path: string, hash: ^sha2.Context_256) -> (offset: u64, ok: bool) {
    data, read_error := os.read_entire_file(manifest_path, context.allocator)
    if read_error != nil {
        return
    }
    defer delete(data)
    // the records that are whole (a header cut off by the interruption at the end of the manifest is dropped)
    records: [dynamic][]byte
    defer delete(records)
    valid_end: int
    for valid_end + 3 <= len(data) {
        path_length: int = int(data[valid_end + 1]) | int(data[valid_end + 2]) << 8
        total: int = 3 + path_length + 1 + 8
        if (data[valid_end] != 1 && data[valid_end] != 2) || path_length == 0 || path_length > BUNDLE_PATH_MAX || valid_end + total > len(data) || len(records) >= BUNDLE_MAX_FILES {
            break
        }
        append(&records, data[valid_end:valid_end + total])
        valid_end += total
    }
    if len(records) == 0 {
        return
    }
    reader^ = {keep_executable = keep_executable}
    reader.root_length = min(len(root), len(reader.root))
    copy(reader.root[:reader.root_length], root)
    for record, index in records {
        path_length: int = len(record) - 3 - 1 - 8
        safe: [BUNDLE_PATH_MAX + 32]byte
        relative, path_ok := BundlePathSafe(safe[:], string(record[3:3 + path_length]))
        if !path_ok {
            return 0, false
        }
        size: u64
        for i in 0 ..< 8 {
            size |= u64(record[3 + path_length + 1 + i]) << uint(8 * i)
        }
        sha2.update(hash, record)
        offset += u64(len(record))
        reader.entries += 1
        if record[0] == 2 {
            if !os.is_dir(fmt.tprintf("%s/%s", root, relative)) {
                return 0, false
            }
            continue
        }
        reader.files += 1
        if size == 0 {
            continue
        }
        full: string = fmt.tprintf("%s/%s", root, relative)
        file, open_error := os.open(full, {.Read, .Write})
        if open_error != nil {
            return 0, false
        }
        on_disk, size_error := os.file_size(file)
        last: bool = index == len(records) - 1
        // every file but the last one must be whole; the last one may be cut anywhere, never longer than it says
        if size_error != nil || u64(on_disk) > size || (!last && u64(on_disk) != size) || !PartHash(file, u64(on_disk), hash) {
            os.close(file)
            return 0, false
        }
        offset += u64(on_disk)
        if last && u64(on_disk) < size {
            os.seek(file, 0, .End)
            reader.file = file
            reader.data_left = size - u64(on_disk)
            reader.state = .DATA
        } else {
            os.close(file)
        }
    }
    // the manifest goes on from the last whole record
    if os.write_entire_file(manifest_path, data[:valid_end]) != nil {
        BundleReaderClose(reader)
        return 0, false
    }
    reader.manifest, _ = os.open(manifest_path, {.Write, .Append})
    return offset, reader.manifest != nil
}

@(private)
BundleFail :: proc(reader: ^BundleReader, why: string) -> bool {
    reader.state = .FAILED
    reader.failure = why
    BundleReaderClose(reader)
    return false
}

// The next piece of the stream, any size. False: invalid (see reader.failure), the caller deletes the staging folder.
BundleFeed :: proc(reader: ^BundleReader, data: []byte) -> bool {
    data: []byte = data
    for len(data) > 0 {
        switch reader.state {
        case .FAILED:
            return false
        case .ENDED:
            return BundleFail(reader, "data after the end of the folder")
        case .DATA:
            count: int = int(min(u64(len(data)), reader.data_left))
            if _, error := os.write(reader.file, data[:count]); error != nil {
                return BundleFail(reader, "cannot write a file of the folder")
            }
            data = data[count:]
            reader.data_left -= u64(count)
            if reader.data_left == 0 {
                os.close(reader.file)
                reader.file = nil
                reader.state = .HEADER
            }
        case .HEADER:
            if reader.header_length == 0 && data[0] == 0 {
                reader.state = .ENDED
                reader.ended = true
                data = data[1:]
                continue
            }
            reader.header[reader.header_length] = data[0]
            reader.header_length += 1
            data = data[1:]
            if reader.header_length == 3 {
                path_length: int = int(reader.header[1]) | int(reader.header[2]) << 8
                if (reader.header[0] != 1 && reader.header[0] != 2) || path_length == 0 || path_length > BUNDLE_PATH_MAX {
                    return BundleFail(reader, "damaged folder record")
                }
                reader.header_need = 3 + path_length + 1 + 8
            }
            if reader.header_length > 3 && reader.header_length == reader.header_need {
                if !BundleRecord(reader) {
                    return false
                }
            }
        }
    }
    return true
}

// The header of the record that was just accepted, still in `reader.header`.
@(private)
BundleManifestAdd :: proc(reader: ^BundleReader, length: int) {
    if reader.manifest != nil {
        os.write(reader.manifest, reader.header[:length])
    }
}

@(private)
BundleRecord :: proc(reader: ^BundleReader) -> bool {
    path_length: int = reader.header_need - 3 - 1 - 8
    wanted: string = string(reader.header[3:3 + path_length])
    flags: u8 = reader.header[3 + path_length]
    size: u64
    for i in 0 ..< 8 {
        size |= u64(reader.header[3 + path_length + 1 + i]) << uint(8 * i)
    }
    kind: u8 = reader.header[0]
    raw_length: int = reader.header_need
    reader.header_length = 0
    reader.entries += 1
    if reader.entries > BUNDLE_MAX_FILES {
        return BundleFail(reader, "too many files in the folder")
    }
    safe: [BUNDLE_PATH_MAX + 32]byte
    relative, ok := BundlePathSafe(safe[:], wanted)
    if !ok {
        return BundleFail(reader, "a path in the folder is not allowed")
    }
    full: string = fmt.tprintf("%s/%s", string(reader.root[:reader.root_length]), relative)
    if kind == 2 {
        if size != 0 {
            return BundleFail(reader, "damaged folder record")
        }
        os.make_directory_all(full)
        BundleManifestAdd(reader, raw_length)
        return true
    }
    parent_end: int = strings.last_index_byte(full, '/')
    if parent_end > 0 {
        os.make_directory_all(full[:parent_end])
    }
    file, error := os.open(full, {.Write, .Create, .Trunc})
    if error != nil {
        return BundleFail(reader, "cannot create a file of the folder")
    }
    reader.files += 1
    BundleManifestAdd(reader, raw_length)
    if size == 0 {
        os.close(file)
    } else {
        reader.file = file
        reader.data_left = size
        reader.state = .DATA
    }
    _ = flags
    when ODIN_OS != .Windows {
        if flags & 1 != 0 && reader.keep_executable {
            os.chmod(full, {.Read_User, .Write_User, .Execute_User, .Read_Group, .Execute_Group, .Read_Other, .Execute_Other})
        }
    }
    return true
}

// ---------------------------------------------------------------------------------------------------------------- tests

@(test)
BundlePathSafeTest :: proc(t: ^testing.T) {
    buffer: [BUNDLE_PATH_MAX + 32]byte
    path, ok := BundlePathSafe(buffer[:], "src/.claude/notes.md")
    testing.expect(t, ok)
    testing.expect_value(t, path, "src/.claude/notes.md")
    path, ok = BundlePathSafe(buffer[:], ".gitignore")
    testing.expect(t, ok)
    testing.expect_value(t, path, ".gitignore")                  // dot files survive in a bundle
    path, ok = BundlePathSafe(buffer[:], "a/b:c/d?.txt")
    testing.expect(t, ok)
    testing.expect_value(t, path, "a/b_c/d_.txt")
    for bad in ([?]string{"../x", "a/../../x", "/etc/passwd", "a//b", "a/./b", "", "con/x"}) {
        _, ok = BundlePathSafe(buffer[:], bad)
        // "con/x" is made safe (_con/x), the others are refused
        testing.expectf(t, ok == (bad == "con/x"), "%q: %v", bad, ok)
    }
    deep: string = strings.repeat("d/", BUNDLE_DEPTH_MAX + 2, context.temp_allocator)
    _, ok = BundlePathSafe(buffer[:], deep)
    testing.expect(t, !ok)
}

WriteTree :: proc(root: string) {
    os.make_directory_all(fmt.tprintf("%s/sub/deep", root))
    os.make_directory_all(fmt.tprintf("%s/empty_dir", root))
    os.make_directory_all(fmt.tprintf("%s/.git", root))
    os.make_directory_all(fmt.tprintf("%s/node_modules/pkg", root))
    _ = os.write_entire_file(fmt.tprintf("%s/a.txt", root), "first file")
    _ = os.write_entire_file(fmt.tprintf("%s/.gitignore", root), "*.o")
    _ = os.write_entire_file(fmt.tprintf("%s/zero.bin", root), "")
    _ = os.write_entire_file(fmt.tprintf("%s/sub/deep/c.txt", root), "deep file")
    _ = os.write_entire_file(fmt.tprintf("%s/.git/config", root), "excluded")
    _ = os.write_entire_file(fmt.tprintf("%s/node_modules/pkg/x.js", root), "excluded")
    _ = os.write_entire_file(fmt.tprintf("%s/skip.tmp", root), "excluded by pattern")
    FillTestFile(fmt.tprintf("%s/sub/big.bin", root), 150_007)
}

// Any chunking of the stream gives the same folder: scan, read in odd sized pieces, feed in other odd sized pieces.
@(test)
BundleRoundTripTest :: proc(t: ^testing.T) {
    folder: string = TempFolder("bundle")
    defer os.remove_all(folder)
    defer delete(folder)
    source: string = fmt.tprintf("%s/project", folder)
    WriteTree(source)

    bundle: Bundle
    testing.expect(t, BundleScan(&bundle, source, {".git", "node_modules", "*.tmp"}, context.allocator))
    defer BundleDestroy(&bundle)
    testing.expect_value(t, bundle.files, 5)                     // a.txt .gitignore zero.bin c.txt big.bin

    stream: [dynamic]byte
    defer delete(stream)
    piece: [313]byte
    for {
        count: int = BundleRead(&bundle, piece[:])
        testing.expect(t, count >= 0)
        append(&stream, ..piece[:max(count, 0)])
        if count < len(piece) {
            break
        }
    }
    testing.expect_value(t, u64(len(stream)), bundle.total)

    for step in ([?]int{1, 7, 800, 100_000}) {
        target: string = fmt.tprintf("%s/out_%d", folder, step)
        reader: BundleReader
        BundleReaderInit(&reader, target, false)
        offset: int
        for offset < len(stream) {
            end: int = min(offset + step, len(stream))
            testing.expectf(t, BundleFeed(&reader, stream[offset:end]), "step %d: %s", step, reader.failure)
            offset = end
        }
        testing.expect(t, reader.ended)
        BundleReaderClose(&reader)
        testing.expect(t, SameFile(fmt.tprintf("%s/sub/big.bin", source), fmt.tprintf("%s/sub/big.bin", target)))
        testing.expect(t, SameFile(fmt.tprintf("%s/.gitignore", source), fmt.tprintf("%s/.gitignore", target)))
        testing.expect(t, SameFile(fmt.tprintf("%s/sub/deep/c.txt", source), fmt.tprintf("%s/sub/deep/c.txt", target)))
        testing.expect(t, os.exists(fmt.tprintf("%s/zero.bin", target)))
        testing.expect(t, os.is_dir(fmt.tprintf("%s/empty_dir", target)))
        testing.expect(t, !os.exists(fmt.tprintf("%s/.git", target)))
        testing.expect(t, !os.exists(fmt.tprintf("%s/node_modules", target)))
        testing.expect(t, !os.exists(fmt.tprintf("%s/skip.tmp", target)))
    }
}

// A stream that tries to write outside, or lies about its size, is refused and leaves nothing outside the staging folder.
@(test)
BundleHostileTest :: proc(t: ^testing.T) {
    folder: string = TempFolder("hostile")
    defer os.remove_all(folder)
    defer delete(folder)

    record :: proc(stream: ^[dynamic]byte, kind: u8, path: string, size: u64) {
        append(stream, kind, u8(len(path)), u8(len(path) >> 8))
        append(stream, ..transmute([]byte)path)
        append(stream, 0)
        for i in 0 ..< 8 {
            append(stream, u8(size >> uint(8 * i)))
        }
    }
    stream: [dynamic]byte
    defer delete(stream)
    record(&stream, 1, "../escaped.txt", 3)
    append(&stream, 'a', 'b', 'c', 0)
    reader: BundleReader
    BundleReaderInit(&reader, fmt.tprintf("%s/stage", folder), false)
    testing.expect(t, !BundleFeed(&reader, stream[:]))
    testing.expect(t, !os.exists(fmt.tprintf("%s/escaped.txt", folder)))

    // data after the end mark
    clear(&stream)
    append(&stream, 0, 1)
    reader = {}
    BundleReaderInit(&reader, fmt.tprintf("%s/stage2", folder), false)
    testing.expect(t, !BundleFeed(&reader, stream[:]))

    // a record that claims a folder with data, and a path length of zero
    clear(&stream)
    record(&stream, 2, "d", 5)
    reader = {}
    BundleReaderInit(&reader, fmt.tprintf("%s/stage3", folder), false)
    testing.expect(t, !BundleFeed(&reader, stream[:]))
    clear(&stream)
    append(&stream, 1, 0, 0)
    reader = {}
    BundleReaderInit(&reader, fmt.tprintf("%s/stage4", folder), false)
    testing.expect(t, !BundleFeed(&reader, stream[:]))
}

// A folder cut off anywhere (inside a header, inside a file, between records) is picked up from its manifest and staging folder: the
// reader says how much of the stream it holds and the hash of that prefix, and the rest of the stream finishes the same folder.
@(test)
BundleResumeTest :: proc(t: ^testing.T) {
    folder: string = TempFolder("bundle_resume")
    defer os.remove_all(folder)
    defer delete(folder)
    source: string = fmt.tprintf("%s/project", folder)
    WriteTree(source)
    bundle: Bundle
    testing.expect(t, BundleScan(&bundle, source, {".git", "node_modules", "*.tmp"}, context.allocator))
    defer BundleDestroy(&bundle)
    stream: [dynamic]byte
    defer delete(stream)
    piece: [1000]byte
    for {
        count: int = BundleRead(&bundle, piece[:])
        append(&stream, ..piece[:max(count, 0)])
        if count < len(piece) {
            break
        }
    }

    for cut, index in ([?]int{5, 20, 40, 1000, 60_000, 150_000, len(stream) - 3}) {
        stage: string = fmt.tprintf("%s/stage_%d", folder, index)
        manifest: string = fmt.tprintf("%s.manifest", stage)
        first: BundleReader
        BundleReaderInit(&first, stage, false, manifest)
        testing.expect(t, BundleFeed(&first, stream[:cut]))
        BundleReaderClose(&first)                                   // the interruption: the staging folder and the manifest stay

        again: BundleReader
        hash: sha2.Context_256
        sha2.init_256(&hash)
        offset, ok := BundleReaderResume(&again, stage, false, manifest, &hash)
        testing.expectf(t, ok || offset == 0, "cut %d", cut)
        if !ok {
            // nothing whole had arrived (a cut inside the first header): the sender starts the folder again
            testing.expect(t, cut < 40)
            BundleReaderClose(&again)
            continue
        }
        testing.expectf(t, offset > 0 && offset <= u64(cut), "cut %d: offset %d", cut, offset)
        expected: sha2.Context_256
        sha2.init_256(&expected)
        sha2.update(&expected, stream[:offset])
        got, want: [HASH_SIZE]byte
        sha2.final(&hash, got[:])
        sha2.final(&expected, want[:])
        testing.expectf(t, string(got[:]) == string(want[:]), "cut %d: the prefix hash differs", cut)

        testing.expectf(t, BundleFeed(&again, stream[offset:]), "cut %d: %s", cut, again.failure)
        testing.expect(t, again.ended)
        BundleReaderClose(&again)
        testing.expect(t, SameFile(fmt.tprintf("%s/sub/big.bin", source), fmt.tprintf("%s/sub/big.bin", stage)))
        testing.expect(t, SameFile(fmt.tprintf("%s/sub/deep/c.txt", source), fmt.tprintf("%s/sub/deep/c.txt", stage)))
        testing.expect(t, os.is_dir(fmt.tprintf("%s/empty_dir", stage)))
        testing.expect(t, os.exists(fmt.tprintf("%s/zero.bin", stage)))
    }

    // a staging folder that lost a file the manifest names: not usable
    stage: string = fmt.tprintf("%s/stage_lost", folder)
    manifest: string = fmt.tprintf("%s.manifest", stage)
    first: BundleReader
    BundleReaderInit(&first, stage, false, manifest)
    testing.expect(t, BundleFeed(&first, stream[:100_000]))
    BundleReaderClose(&first)
    os.remove(fmt.tprintf("%s/a.txt", stage))
    again: BundleReader
    hash: sha2.Context_256
    sha2.init_256(&hash)
    _, ok := BundleReaderResume(&again, stage, false, manifest, &hash)
    testing.expect(t, !ok)
    BundleReaderClose(&again)
}
