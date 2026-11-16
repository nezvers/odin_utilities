#+build !js
package youtube_shorts

import "core:strings"
import "core:testing"

@(test)
test_parse_url :: proc(t: ^testing.T) {
    id, ok := ShortsParseUrl("https://www.youtube.com/shorts/dQw4w9WgXcQ")
    testing.expect(t, ok)
    testing.expect_value(t, id, "dQw4w9WgXcQ")

    id, ok = ShortsParseUrl("https://m.youtube.com/shorts/dQw4w9WgXcQ?feature=share&t=3#x")
    testing.expect(t, ok, "query and fragment end the id")
    testing.expect_value(t, id, "dQw4w9WgXcQ")

    id, ok = ShortsParseUrl("http://youtube.com/shorts/aaaaaaaaaaa/")
    testing.expect(t, ok)
    testing.expect_value(t, id, "aaaaaaaaaaa")

    // what is not a short stays alone
    for url in ([]string{
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/",
        "https://www.youtube.com/shorts/short",
        "https://www.youtube.com/shorts/dQw4w9WgXcQextra",
        "https://www.youtube.com/shorts/dQw4w9W cQ",
        "https://example.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com.evil.com/shorts/dQw4w9WgXcQ",
        "ftp://www.youtube.com/shorts/dQw4w9WgXcQ",
        "",
    }) {
        _, found := ShortsParseUrl(url)
        testing.expectf(t, !found, "%q is not a short", url)
    }
}

@(test)
test_watch_url :: proc(t: ^testing.T) {
    buffer: [64]u8
    testing.expect_value(t, ShortsWatchUrl("dQw4w9WgXcQ", buffer[:]), "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
}

@(test)
test_settings_text :: proc(t: ^testing.T) {
    buffer: [32]u8
    text: string = ShortsSettingsEncode({redirect = true, show_save = false}, buffer[:])
    testing.expect_value(t, text, "redirect=1 save=0 download=0")
    testing.expect_value(t, ShortsSettingsDecode(text, SETTINGS_DEFAULT), Settings{redirect = true, show_save = false})
    // a missing key keeps the base, an unknown key is ignored
    testing.expect_value(t, ShortsSettingsDecode("future=1 redirect=1", {show_save = true}), Settings{redirect = true, show_save = true})
}

@(test)
test_toggle_keeps_newest_first :: proc(t: ^testing.T) {
    store: Store
    StoreInit(&store)
    testing.expect_value(t, StoreToggle(&store, "aaaaaaaaaaa", "first"), ToggleResult.ADDED)
    testing.expect_value(t, StoreToggle(&store, "bbbbbbbbbbb", "second"), ToggleResult.ADDED)
    testing.expect_value(t, store.count, 2)
    testing.expect_value(t, string(store.saved[0].id[:]), "bbbbbbbbbbb")
    testing.expect_value(t, StoreToggle(&store, "aaaaaaaaaaa", ""), ToggleResult.REMOVED)
    testing.expect_value(t, store.count, 1)
    testing.expect_value(t, string(store.saved[0].id[:]), "bbbbbbbbbbb")
    testing.expect_value(t, StoreToggle(&store, "nope", "x"), ToggleResult.INVALID)
}

@(test)
test_full_list_fails_instead_of_growing :: proc(t: ^testing.T) {
    store: Store
    StoreInit(&store)
    id: [SHORT_ID_LENGTH]u8
    for i in 0 ..< MAX_SAVED {
        for &character in id { character = 'a' }
        id[0] = 'a' + u8(i % 26)
        id[1] = 'a' + u8(i / 26)
        testing.expect_value(t, StoreToggle(&store, string(id[:]), "t"), ToggleResult.ADDED)
    }
    testing.expect_value(t, StoreToggle(&store, "zzzzzzzzzzz", "t"), ToggleResult.FULL)
    testing.expect_value(t, store.count, MAX_SAVED)
}

@(test)
test_title_is_cleaned_and_cut :: proc(t: ^testing.T) {
    store: Store
    StoreInit(&store)
    StoreToggle(&store, "aaaaaaaaaaa", "tab\there\nline")
    testing.expect_value(t, StoreTitle(&store.saved[0]), "tab here line")

    // 79 bytes and then a two byte character: the cut at 80 would split it
    long: string = strings.concatenate({strings.repeat("x", 79, context.temp_allocator), "é"}, context.temp_allocator)
    StoreToggle(&store, "bbbbbbbbbbb", long)
    title: string = StoreTitle(&store.saved[0])
    testing.expect_value(t, len(title), 79)
}

@(test)
test_state_round_trip :: proc(t: ^testing.T) {
    store, back: Store
    StoreInit(&store)
    store.settings = {redirect = true, show_save = false}
    StoreToggle(&store, "aaaaaaaaaaa", "Cat falls")
    StoreToggle(&store, "bbbbbbbbbbb", "Dog jumps")

    buffer: [STATE_CAPACITY]u8
    text: string = StoreEncode(&store, buffer[:])
    StoreDecode(&back, text)
    testing.expect_value(t, back.settings, store.settings)
    testing.expect_value(t, back.count, 2)
    testing.expect_value(t, string(back.saved[0].id[:]), "bbbbbbbbbbb")
    testing.expect_value(t, StoreTitle(&back.saved[1]), "Cat falls")

    // damaged lines and an empty storage do no harm
    StoreDecode(&back, "")
    testing.expect_value(t, back.settings, SETTINGS_DEFAULT)
    StoreDecode(&back, "redirect=1 save=1\nbroken\n\tno id\naaaaaaaaaaa\tgood\naaaaaaaaaaa\tduplicate\n")
    testing.expect_value(t, back.count, 1)
    testing.expect_value(t, StoreTitle(&back.saved[0]), "good")
}

@(test)
test_messages :: proc(t: ^testing.T) {
    store: Store
    StoreInit(&store)
    reply: [1024]u8
    ask :: proc(store: ^Store, reply: []u8, message: string) -> (string, bool) {
        length, changed := ShortsHandle(store, message, reply)
        return string(reply[:length]), changed
    }

    text, changed := ask(&store, reply[:], "url:https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    testing.expect_value(t, text, "ok")
    testing.expect(t, !changed)

    text, _ = ask(&store, reply[:], "url:https://www.youtube.com/shorts/dQw4w9WgXcQ")
    testing.expect_value(t, text, "short:dQw4w9WgXcQ 0 1 1")
    ask(&store, reply[:], "toggle:dQw4w9WgXcQ	Cat")
    text, _ = ask(&store, reply[:], "url:https://www.youtube.com/shorts/dQw4w9WgXcQ")
    testing.expect_value(t, text, "short:dQw4w9WgXcQ 1 1 1")
    ask(&store, reply[:], "set:save=0")
    text, _ = ask(&store, reply[:], "url:https://www.youtube.com/shorts/dQw4w9WgXcQ")
    testing.expect_value(t, text, "short:dQw4w9WgXcQ 1 0 1")
    ask(&store, reply[:], "remove:dQw4w9WgXcQ")
    ask(&store, reply[:], "set:save=1")

    text, changed = ask(&store, reply[:], "set:redirect=1")
    testing.expect_value(t, text, "redirect=1 save=1 download=1")
    testing.expect(t, changed)

    text, _ = ask(&store, reply[:], "url:https://www.youtube.com/shorts/dQw4w9WgXcQ?feature=share")
    testing.expect_value(t, text, "redirect:https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    text, _ = ask(&store, reply[:], "url:https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    testing.expect_value(t, text, "ok")

    text, changed = ask(&store, reply[:], "toggle:aaaaaaaaaaa\tA title")
    testing.expect_value(t, text, "saved:1")
    testing.expect(t, changed)
    text, _ = ask(&store, reply[:], "has:aaaaaaaaaaa")
    testing.expect_value(t, text, "saved:1")
    text, _ = ask(&store, reply[:], "list")
    testing.expect_value(t, text, "list\naaaaaaaaaaa\tA title\n")
    text, changed = ask(&store, reply[:], "remove:aaaaaaaaaaa")
    testing.expect(t, changed)
    text, changed = ask(&store, reply[:], "remove:aaaaaaaaaaa")
    testing.expect(t, !changed, "nothing to remove, nothing to keep")
    text, _ = ask(&store, reply[:], "list")
    testing.expect_value(t, text, "list\n")
    text, _ = ask(&store, reply[:], "toggle:bad")
    testing.expect_value(t, text, "invalid")
    text, _ = ask(&store, reply[:], "what")
    testing.expect_value(t, text, "unknown")

    // download: the background asks the helper and only forwards what it answers
    text, _ = ask(&store, reply[:], "ytdl?")
    testing.expect_value(t, text, "native:check")
    text, _ = ask(&store, reply[:], "native-reply:ytdl:ok yt-dlp 2026.08.19")
    testing.expect_value(t, text, "ytdl:ok")
    testing.expect_value(t, store.ytdl, YtdlState.OK)
    text, _ = ask(&store, reply[:], "download:dQw4w9WgXcQ")
    testing.expect_value(t, text, "native:download:dQw4w9WgXcQ")
    text, _ = ask(&store, reply[:], "download:bad")
    testing.expect_value(t, text, "invalid")
    text, _ = ask(&store, reply[:], "native-reply:job:dQw4w9WgXcQ")
    testing.expect_value(t, text, "job:dQw4w9WgXcQ")
    text, _ = ask(&store, reply[:], "status:dQw4w9WgXcQ")
    testing.expect_value(t, text, "native:status:dQw4w9WgXcQ")

    // youtube-dl missing: no download is started, the page is told, install and the links are what is left
    ask(&store, reply[:], "native-reply:ytdl:missing")
    testing.expect_value(t, store.ytdl, YtdlState.MISSING)
    text, _ = ask(&store, reply[:], "download:dQw4w9WgXcQ")
    testing.expect_value(t, text, "ytdl:missing")
    text, _ = ask(&store, reply[:], "install")
    testing.expect_value(t, text, "native:install")
    text, _ = ask(&store, reply[:], "links")
    testing.expect(t, strings.contains(text, "repository=https://github.com/yt-dlp/yt-dlp alternative=https://github.com/ytdl-org/youtube-dl "))

    // no helper at all
    text, _ = ask(&store, reply[:], "native-error:Specified native messaging host not found.")
    testing.expect_value(t, text, "ytdl:nohelper")
}
