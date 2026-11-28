#+build !js
package browser_drive

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import web_serve "../web_serve"

// The examples of RFC 6455
@(test)
test_the_accept_key_and_the_frames_of_the_rfc :: proc(t: ^testing.T) {
    buffer: [32]u8
    testing.expect_value(t, WebSocketAccept("dGhlIHNhbXBsZSBub25jZQ==", buffer[:]), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    // a masked "Hello" (5.7): 81 85 37 fa 21 3d 7f 9f 4d 51 58
    out: [32]u8
    length: int = FrameEncode(out[:], .TEXT, transmute([]u8)string("Hello"), {0x37, 0xfa, 0x21, 0x3d})
    expected := [?]u8{0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58}
    testing.expect_value(t, length, len(expected))
    testing.expect(t, string(out[:length]) == string(expected[:]), "the masked frame of the RFC")
    frame, used, complete := FrameParse(out[:length])
    testing.expect(t, complete && used == length && frame.fin && frame.opcode == .TEXT && frame.masked, "it parses back")
    testing.expect_value(t, string(frame.payload), "Hello")

    // an unmasked frame of a server: 81 05 "Hello"; a half frame is not complete
    server := [?]u8{0x81, 0x05, 'H', 'e', 'l', 'l', 'o'}
    frame, used, complete = FrameParse(server[:])
    testing.expect(t, complete && used == 7 && !frame.masked && string(frame.payload) == "Hello")
    _, _, complete = FrameParse(server[:5])
    testing.expect(t, !complete, "the payload is not all there")
    _, _, complete = FrameParse(server[:1])
    testing.expect(t, !complete, "not even the length")
}

// The three length forms (7 bit, 16 bit, 64 bit) round trip
@(test)
test_frames_of_every_length_form_round_trip :: proc(t: ^testing.T) {
    for size in ([?]int{0, 1, 125, 126, 300, 65535, 65536, 70000}) {
        payload: []u8 = make([]u8, size, context.temp_allocator)
        for i in 0 ..< size { payload[i] = u8(i * 7) }
        out: []u8 = make([]u8, size + 16, context.temp_allocator)
        length: int = FrameEncode(out, .BINARY, payload, {1, 2, 3, 4})
        testing.expectf(t, length > 0, "size %d fits", size)
        frame, used, complete := FrameParse(out[:length])
        ok: bool = complete && used == length && len(frame.payload) == size
        if ok { for i in 0 ..< size { if frame.payload[i] != u8(i * 7) { ok = false } } }
        testing.expectf(t, ok, "size %d round trips", size)
    }
    small: [4]u8
    testing.expect_value(t, FrameEncode(small[:], .TEXT, transmute([]u8)string("too long"), {}), 0)
}

@(private = "file")
PAGE :: `<!doctype html><title>start</title><link rel="icon" href="data:,">
<body style="margin:0">
<button style="position:absolute;left:10px;top:10px;width:100px;height:40px" onclick="document.title='clicked'">go</button>
<button style="position:absolute;left:10px;top:60px;width:100px;height:40px" onclick="console.error('boom from the page')">error</button>
<button style="position:absolute;left:10px;top:110px;width:100px;height:40px" onclick="pick()">file</button>
<button style="position:absolute;left:10px;top:160px;width:100px;height:40px" onclick="save()">save</button>
<input id="field" style="position:absolute;left:10px;top:210px;width:200px;height:30px">
<button style="position:absolute;left:10px;top:260px;width:100px;height:40px" onclick="paint()">paint</button>
<div id="box" style="position:absolute;left:250px;top:10px;width:80px;height:80px;background:blue"></div>
<script>
function pick() { const i = document.createElement('input'); i.type = 'file'; i.onchange = () => { document.title = 'file:' + i.files[0].name + ':' + i.files[0].size; }; document.body.appendChild(i); i.click(); }
function paint() { setTimeout(() => { document.getElementById("box").style.background = "red"; }, 400); }
function save() { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['hello'])); a.download = 'x.txt'; document.body.appendChild(a); a.click(); }
</script>`

@(private = "file")
ServeJob :: struct {
    server: ^web_serve.Server,
    stop: bool,
}

// A page with a button for each thing the driver does, served from a folder in the temp directory
@(private = "file")
drivePage :: proc(t: ^testing.T, browser: Browser) {
    if len(BrowserFind(browser)) == 0 {
        fmt.printfln("%s is not installed: its driver test is skipped", BrowserName(browser))
        return
    }
    temp, _ := os.temp_directory(context.temp_allocator)
    directory: string = fmt.tprintf("%s/odin_utilities_browser_drive_test_%s", temp, BrowserName(browser))
    os.remove_all(directory)
    os.make_directory_all(directory)
    defer os.remove_all(directory)
    testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/index.html", directory), PAGE), nil)
    upload: string = fmt.tprintf("%s/upload.txt", directory)
    testing.expect_value(t, os.write_entire_file(upload, "12345"), nil)

    server: web_serve.Server
    if !web_serve.ServerInit(&server, {directory = directory, port = 0}) { testing.fail_now(t, "no free port") }
    defer web_serve.ServerShutdown(&server)
    job: ServeJob = {server = &server}
    runner: ^thread.Thread = thread.create_and_start_with_poly_data(&job, proc(job: ^ServeJob) { web_serve.ServerRun(job.server, &job.stop) })
    defer {
        sync.atomic_store(&job.stop, true)
        thread.join(runner)
        thread.destroy(runner)
    }

    driver: ^Driver = new(Driver)
    defer free(driver)
    name: string = BrowserName(browser)
    if error := DriverStart(driver, {browser = browser}); error != .NONE { testing.expectf(t, false, "%s starts: %v %s", name, error, DriverLastError(driver)); return }
    defer DriverStop(driver)

    testing.expectf(t, DriverNavigate(driver, fmt.tprintf("http://127.0.0.1:%d/", server.port)) == .NONE, "%s loads the page: %s", name, DriverLastError(driver))
    value, error := DriverEvaluate(driver, "1 + 1")
    testing.expectf(t, error == .NONE && value == "2", "%s evaluates: %q %v", name, value, error)
    value, _ = DriverEvaluate(driver, "document.title")
    testing.expect_value(t, value, "start")
    _, error = DriverEvaluate(driver, "thisDoesNotExist()")
    testing.expectf(t, error == .SCRIPT, "%s: an exception in the page is a SCRIPT error: %v", name, error)

    // a click
    DriverClick(driver, 30, 30)
    DriverWait(driver, 300)
    value, _ = DriverEvaluate(driver, "document.title")
    testing.expectf(t, value == "clicked", "%s clicks a button: title is %q", name, value)

    // what the page writes to its console as an error
    testing.expect_value(t, DriverConsoleErrors(driver), "")
    DriverClick(driver, 30, 80)
    DriverWait(driver, 500)
    testing.expectf(t, strings.contains(DriverConsoleErrors(driver), "boom from the page"), "%s collects console errors: %q", name, DriverConsoleErrors(driver))

    // the picture: a page that changes a moment after a click (a canvas has no event for that) is waited for by what it looks like
    testing.expect_value(t, DriverWaitStable(driver), Error.NONE)
    before, hash_error := DriverPictureHash(driver)
    testing.expect_value(t, hash_error, Error.NONE)
    again, _ := DriverPictureHash(driver)
    testing.expectf(t, before == again, "%s: the same page has the same picture hash", name)
    DriverClick(driver, 30, 280)
    testing.expect_value(t, DriverWaitChanged(driver, before, 700), Error.NONE) // the click itself changes the button (focus, hover): the quiet time has to be longer than the 400 ms of the page
    value, _ = DriverEvaluate(driver, "document.getElementById('box').style.background")
    testing.expectf(t, value == "red", "%s: the page was drawn again when the wait ended: %q", name, value)

    // typing into a field
    DriverClick(driver, 30, 225)
    DriverType(driver, "abc")
    value, _ = DriverEvaluate(driver, "document.getElementById('field').value")
    testing.expectf(t, value == "abc", "%s types: %q", name, value)

    // a file chooser, answered with a file
    DriverAnswerFileChooser(driver, upload)
    DriverClick(driver, 30, 130)
    DriverWait(driver, 1500)
    value, _ = DriverEvaluate(driver, "document.title")
    testing.expectf(t, strings.has_prefix(value, "file:upload.txt:5"), "%s answers the file chooser: title is %q", name, value)
    testing.expect_value(t, DriverFileDialogs(driver), 1)

    // a download
    testing.expect_value(t, DriverTrackDownloads(driver), Error.NONE)
    DriverClick(driver, 30, 180)
    DriverWait(driver, 800)
    testing.expect_value(t, DriverDownloads(driver), "x.txt:5")

    // a picture
    shot: string = fmt.tprintf("%s/shot.png", directory)
    testing.expect_value(t, DriverScreenshot(driver, shot), Error.NONE)
    data, read_error := os.read_entire_file(shot, context.temp_allocator)
    testing.expectf(t, read_error == nil && len(data) > 100 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G', "%s writes a PNG", name)
}

@(test)
test_chrome_is_driven :: proc(t: ^testing.T) { drivePage(t, .CHROME) }

@(test)
test_edge_is_driven :: proc(t: ^testing.T) { drivePage(t, .EDGE) }

@(test)
test_firefox_is_driven :: proc(t: ^testing.T) { drivePage(t, .FIREFOX) }
