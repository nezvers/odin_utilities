// The logic of the YouTube Shorts extension, no browser and no framework in it, so it runs in the background (wasm), in the options page
// and in tests alike:
//   - Shorts addresses (youtube.com/shorts/<id>) and the full video address of the same video (youtube.com/watch?v=<id>)
//   - the two options and the list of saved shorts (fixed capacity, newest first) with their text form for the browser storage
//   - the messages the content script and the options page send (ShortsHandle)
// The JavaScript around it only reads the page and moves text, every decision is made here.
package youtube_shorts

import "core:fmt"
import "core:strings"

SHORT_ID_LENGTH :: 11
MAX_SAVED :: 64
TITLE_CAPACITY :: 80

// Written to the browser storage and read back from it, about 6 KB when the list is full
STATE_CAPACITY :: 8 * 1024

Settings :: struct {
    redirect: bool,     // open a short in the normal player (youtube.com/watch?v=<id>) instead of the Shorts player
    show_save: bool,    // a Save button next to the native buttons of the Shorts player
    show_download: bool,// a Download button below it, it runs yt-dlp or youtube-dl (whichever is on PATH) through the native helper
}

SETTINGS_DEFAULT :: Settings{redirect = false, show_save = true, show_download = true}

// Where the buttons of the page send you. The addresses live here so the JavaScript has none.
YTDL_REPOSITORY :: "https://github.com/yt-dlp/yt-dlp"
YTDL_ALTERNATIVE :: "https://github.com/ytdl-org/youtube-dl"
YTDL_INSTALL_GUIDE :: "https://github.com/yt-dlp/yt-dlp/wiki/Installation"
HELPER_GUIDE :: "https://github.com/nezvers/odin_utilities/tree/main/browser_extension/youtube_shorts#download-helper"

// What the native helper said about yt-dlp / youtube-dl the last time it was asked. Not kept in the storage: it is looked up again on every page.
YtdlState :: enum {
    UNKNOWN,
    OK,
    MISSING,
}

SavedShort :: struct {
    id: [SHORT_ID_LENGTH]u8,
    title: [TITLE_CAPACITY]u8,
    title_length: int,
}

// All the state of the extension. Plain data, no pointers: lives in a global of the background or on the stack of a test.
Store :: struct {
    settings: Settings,
    ytdl: YtdlState,
    saved: [MAX_SAVED]SavedShort,   // newest first
    count: int,
}

ToggleResult :: enum {
    INVALID,
    ADDED,
    REMOVED,
    FULL,
}

StoreInit :: proc(store: ^Store) {
    store^ = {settings = SETTINGS_DEFAULT}
}

// --- Addresses ---

// A video id is 11 letters, digits, - and _
ShortsIsId :: proc(text: string) -> bool {
    if len(text) != SHORT_ID_LENGTH {
        return false
    }
    for character in text {
        switch character {
        case 'a'..='z', 'A'..='Z', '0'..='9', '-', '_':
        case:
            return false
        }
    }
    return true
}

// The id of a Shorts address: "https://www.youtube.com/shorts/<id>?feature=share" -> id. Other addresses (watch, channel, ...) are not ok.
ShortsParseUrl :: proc(url: string) -> (id: string, ok: bool) {
    rest: string = url
    if strings.has_prefix(rest, "https://") {
        rest = rest[len("https://"):]
    } else if strings.has_prefix(rest, "http://") {
        rest = rest[len("http://"):]
    } else {
        return
    }
    slash: int = strings.index_byte(rest, '/')
    if slash < 0 {
        return
    }
    host: string = rest[:slash]
    if host != "www.youtube.com" && host != "youtube.com" && host != "m.youtube.com" {
        return
    }
    path: string = rest[slash:]
    if !strings.has_prefix(path, "/shorts/") {
        return
    }
    path = path[len("/shorts/"):]
    // the id ends at the query, the fragment or the next slash
    end: int = strings.index_any(path, "?#/")
    candidate: string = path if end < 0 else path[:end]
    if !ShortsIsId(candidate) {
        return
    }
    return candidate, true
}

// The full video address of the id: the normal player, with the recommendations, the timeline and the description
ShortsWatchUrl :: proc(id: string, buffer: []u8) -> string {
    assert(ShortsIsId(id))
    return fmt.bprintf(buffer, "https://www.youtube.com/watch?v=%s", id)
}

// --- Settings ---

// "redirect=1 save=1 download=1"
ShortsSettingsEncode :: proc(settings: Settings, buffer: []u8) -> string {
    return fmt.bprintf(buffer, "redirect=%d save=%d download=%d", int(settings.redirect), int(settings.show_save), int(settings.show_download))
}

// Keys that are not in the text keep their value of `base`, unknown keys are ignored: a newer options page can talk to an older background
ShortsSettingsDecode :: proc(text: string, base: Settings) -> Settings {
    settings: Settings = base
    remaining: string = text
    for field in strings.split_iterator(&remaining, " ") {
        equals: int = strings.index_byte(field, '=')
        if equals < 0 {
            continue
        }
        value: bool = field[equals + 1:] == "1"
        switch field[:equals] {
        case "redirect": settings.redirect = value
        case "save": settings.show_save = value
        case "download": settings.show_download = value
        }
    }
    return settings
}

// --- Saved shorts ---

StoreFind :: proc(store: ^Store, id: string) -> int {
    for i in 0 ..< store.count {
        if string(store.saved[i].id[:]) == id {
            return i
        }
    }
    return -1
}

StoreTitle :: proc(short: ^SavedShort) -> string {
    return string(short.title[:short.title_length])
}

// The title as it is kept: control characters (tab and newline are separators of the text form) become spaces, a title that is too long is
// cut, never in the middle of a UTF-8 character
@(private)
shortsSetTitle :: proc(short: ^SavedShort, title: string) {
    length: int = min(len(title), TITLE_CAPACITY)
    for length > 0 && length < len(title) && (title[length] & 0xC0) == 0x80 {
        length -= 1
    }
    for i in 0 ..< length {
        short.title[i] = title[i] if title[i] >= 0x20 else ' '
    }
    short.title_length = length
}

// Adds a short, or removes it when it is saved already. The new one goes to the front.
StoreToggle :: proc(store: ^Store, id: string, title: string) -> ToggleResult {
    if !ShortsIsId(id) {
        return .INVALID
    }
    index: int = StoreFind(store, id)
    if index >= 0 {
        StoreRemoveAt(store, index)
        return .REMOVED
    }
    if store.count >= MAX_SAVED {
        return .FULL
    }
    copy(store.saved[1:store.count + 1], store.saved[:store.count])
    store.saved[0] = {}
    copy(store.saved[0].id[:], id)
    shortsSetTitle(&store.saved[0], title)
    store.count += 1
    return .ADDED
}

StoreRemoveAt :: proc(store: ^Store, index: int) {
    assert(index >= 0 && index < store.count)
    copy(store.saved[index:store.count - 1], store.saved[index + 1:store.count])
    store.count -= 1
    store.saved[store.count] = {}
}

// --- Text form of the state ---

// First line the settings, then one line per saved short: "<id>\t<title>". Newest first.
StoreEncode :: proc(store: ^Store, buffer: []u8) -> string {
    builder: strings.Builder = strings.builder_from_bytes(buffer)
    settings: [48]u8
    fmt.sbprintfln(&builder, "%s", ShortsSettingsEncode(store.settings, settings[:]))
    for i in 0 ..< store.count {
        fmt.sbprintfln(&builder, "%s\t%s", string(store.saved[i].id[:]), StoreTitle(&store.saved[i]))
    }
    return strings.to_string(builder)
}

// Reads what StoreEncode wrote. Lines that do not parse are skipped: the storage may hold an older or damaged text.
StoreDecode :: proc(store: ^Store, text: string) {
    StoreInit(store)
    remaining: string = text
    first: bool = true
    for line in strings.split_lines_iterator(&remaining) {
        if first {
            store.settings = ShortsSettingsDecode(line, SETTINGS_DEFAULT)
            first = false
            continue
        }
        tab: int = strings.index_byte(line, '\t')
        if tab < 0 || !ShortsIsId(line[:tab]) || store.count >= MAX_SAVED || StoreFind(store, line[:tab]) >= 0 {
            continue
        }
        // appended in file order: the file is newest first already
        short: ^SavedShort = &store.saved[store.count]
        copy(short.id[:], line[:tab])
        shortsSetTitle(short, line[tab + 1:])
        store.count += 1
    }
}

// --- Messages ---

// What the content script and the options page send, one text each:
//   url:<address>            -> a short and the redirect option is on: "redirect:<full video address>"
//                               a short: "short:<id> <saved 0|1> <show Save 0|1> <show Download 0|1>", anything else: "ok"
//   get                      -> the settings text
//   set:<settings text>      -> the settings text as kept
//   has:<id>                 -> "saved:1" or "saved:0"
//   toggle:<id>\t<title>     -> "saved:1" (added), "saved:0" (removed), "full" or "invalid"
//   remove:<id>              -> "ok"
//   list                     -> "list", then one line "<id>\t<title>" per saved short, newest first
// Download through yt-dlp or youtube-dl (the page only shows what comes back):
//   links                    -> "repository=<yt-dlp url> alternative=<youtube-dl url> install=<url> helper=<url>"
//   ytdl?                    -> asks the native helper; the final reply is "ytdl:ok", "ytdl:missing" or "ytdl:nohelper" (helper not installed)
//   download:<id>            -> "job:<id>" (started), or "ytdl:missing" / "ytdl:nohelper"
//   install                  -> "job:install": the helper installs yt-dlp (downloads the release on Windows, pip elsewhere)
//   status:<id|install>      -> "status:running", "status:done <file>", "status:failed <code>" or "status:none"
// A reply "native:<text>" is not for the page: the background sends the text to the native helper and hands its answer back as
// "native-reply:<text>" (or "native-error:<why>"), the reply to that is the one the page gets.
// Returns the length of the reply and whether the state changed (then the caller keeps it with StoreEncode).
ShortsHandle :: proc(store: ^Store, message: string, reply: []u8) -> (length: int, changed: bool) {
    switch {
    case strings.has_prefix(message, "url:"):
        id, ok := ShortsParseUrl(message[len("url:"):])
        if !ok {
            return reply_text(reply, "ok"), false
        }
        if store.settings.redirect {
            url: [64]u8
            return reply_text(reply, "redirect:", ShortsWatchUrl(id, url[:])), false
        }
        // the Shorts player stays: the page needs to know which buttons to add and how the Save button looks
        return reply_text(reply, "short:", id, " ", flag(StoreFind(store, id) >= 0), " ", flag(store.settings.show_save), " ", flag(store.settings.show_download)), false

    case message == "get":
        return len(ShortsSettingsEncode(store.settings, reply)), false

    case strings.has_prefix(message, "set:"):
        store.settings = ShortsSettingsDecode(message[len("set:"):], store.settings)
        return len(ShortsSettingsEncode(store.settings, reply)), true

    case strings.has_prefix(message, "has:"):
        found: bool = StoreFind(store, message[len("has:"):]) >= 0
        return reply_text(reply, "saved:1" if found else "saved:0"), false

    case strings.has_prefix(message, "toggle:"):
        body: string = message[len("toggle:"):]
        tab: int = strings.index_byte(body, '\t')
        id: string = body if tab < 0 else body[:tab]
        title: string = "" if tab < 0 else body[tab + 1:]
        switch StoreToggle(store, id, title) {
        case .ADDED: return reply_text(reply, "saved:1"), true
        case .REMOVED: return reply_text(reply, "saved:0"), true
        case .FULL: return reply_text(reply, "full"), false
        case .INVALID: return reply_text(reply, "invalid"), false
        }

    case strings.has_prefix(message, "remove:"):
        index: int = StoreFind(store, message[len("remove:"):])
        if index >= 0 {
            StoreRemoveAt(store, index)
        }
        return reply_text(reply, "ok"), index >= 0

    case message == "links":
        return reply_text(reply, "repository=", YTDL_REPOSITORY, " alternative=", YTDL_ALTERNATIVE, " install=", YTDL_INSTALL_GUIDE, " helper=", HELPER_GUIDE), false

    case message == "ytdl?":
        return reply_text(reply, "native:check"), false

    case strings.has_prefix(message, "download:"):
        id: string = message[len("download:"):]
        if !ShortsIsId(id) {
            return reply_text(reply, "invalid"), false
        }
        if store.ytdl == .MISSING {
            return reply_text(reply, "ytdl:missing"), false
        }
        return reply_text(reply, "native:", message), false

    case message == "install":
        return reply_text(reply, "native:install"), false

    case strings.has_prefix(message, "status:"):
        return reply_text(reply, "native:", message), false

    case strings.has_prefix(message, "native-reply:"):
        answer: string = message[len("native-reply:"):]
        switch {
        case strings.has_prefix(answer, "ytdl:ok"): store.ytdl = .OK
        case strings.has_prefix(answer, "ytdl:missing"): store.ytdl = .MISSING
        }
        // "ytdl:ok 2026.08.19" -> "ytdl:ok": the page needs no version
        space: int = strings.index_byte(answer, ' ')
        return reply_text(reply, answer if space < 0 || !strings.has_prefix(answer, "ytdl:") else answer[:space]), false

    case strings.has_prefix(message, "native-error:"):
        // the browser could not reach the helper: it is not installed (or not registered for this browser)
        return reply_text(reply, "ytdl:nohelper"), false

    case message == "list":
        // the first line names the reply: replies reach a page one by one and without the request they answer
        builder: strings.Builder = strings.builder_from_bytes(reply)
        strings.write_string(&builder, "list\n")
        for i in 0 ..< store.count {
            fmt.sbprintfln(&builder, "%s\t%s", string(store.saved[i].id[:]), StoreTitle(&store.saved[i]))
        }
        return len(strings.to_string(builder)), false
    }
    return reply_text(reply, "unknown"), false
}

@(private)
flag :: proc(value: bool) -> string {
    return "1" if value else "0"
}

// The parts one after the other into the reply, cut when it does not fit
@(private)
reply_text :: proc(reply: []u8, parts: ..string) -> int {
    length: int
    for part in parts {
        length += copy(reply[length:], part)
    }
    return length
}
