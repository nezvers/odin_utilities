#+build !js
// Install a temporary add-on in a running Firefox over its remote debugging protocol, what `web-ext run` does.
// Protocol: every packet is `<byte length>:<json>`, the server speaks first (a greeting), then a request names the actor it is for.
// Ask the root actor for `addonsActor`, send it `installTemporaryAddon` with the folder. Unsigned add-ons load this way until Firefox closes.
package browser_extension

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"

RDP_PACKET_CAPACITY :: 256 * 1024
RDP_CONNECT_TIMEOUT :: 30 * time.Second
RDP_REPLY_TIMEOUT :: 10 * time.Second

// Packets go through one fixed buffer, a packet that does not fit fails the install instead of growing it
@(private)
RdpConnection :: struct {
    socket: net.TCP_Socket,
    buffer: [RDP_PACKET_CAPACITY]u8,
    filled: int,
}

// Prefs of the profile: the debugging server is allowed without a prompt and unsigned add-ons may load where the build allows it
@(private)
FIREFOX_USER_PREFS :: `user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.debugger.prompt-connection", false);
user_pref("devtools.chrome.enabled", true);
user_pref("xpinstall.signatures.required", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "about:blank");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
`

@(private)
RdpConnect :: proc(connection: ^RdpConnection, port: int) -> bool {
    socket, error := net.dial_tcp_from_address_and_port(net.IP4_Loopback, port)
    if error != nil {
        return false
    }
    connection.socket = socket
    connection.filled = 0
    net.set_option(socket, .Receive_Timeout, RDP_REPLY_TIMEOUT)
    return true
}

// Reads one packet and returns its json text, valid until the next RdpReceive
@(private)
RdpReceive :: proc(connection: ^RdpConnection) -> (text: string, ok: bool) {
    colon: int = -1
    length: int
    for {
        if colon < 0 {
            colon = strings.index_byte(string(connection.buffer[:connection.filled]), ':')
            if colon >= 0 {
                parsed: bool
                length, parsed = strconv.parse_int(string(connection.buffer[:colon]))
                if !parsed || length < 0 || colon + 1 + length > RDP_PACKET_CAPACITY {
                    return
                }
            }
        }
        if colon >= 0 && connection.filled >= colon + 1 + length {
            break
        }
        count, error := net.recv_tcp(connection.socket, connection.buffer[connection.filled:])
        if error != nil || count == 0 {
            return
        }
        connection.filled += count
    }
    text = string(connection.buffer[colon + 1:colon + 1 + length])
    // the next packet moves to the front, `text` stays valid until the following receive overwrites it
    return text, true
}

@(private)
RdpConsume :: proc(connection: ^RdpConnection, text: string) {
    end: int = (int(uintptr(raw_data(text))) - int(uintptr(&connection.buffer[0]))) + len(text)
    copy(connection.buffer[:], connection.buffer[end:connection.filled])
    connection.filled -= end
}

@(private)
RdpSend :: proc(connection: ^RdpConnection, actor, type: string, extra_key := "", extra_value := "") -> bool {
    Request :: struct {
        to: string `json:"to"`,
        type: string `json:"type"`,
        addonPath: string `json:"addonPath,omitempty"`,
        openDevTools: bool `json:"openDevTools"`,
    }
    request: Request = {to = actor, type = type}
    if extra_key == "addonPath" {
        request.addonPath = extra_value
    }
    body, error := json.marshal(request, allocator = context.temp_allocator)
    if error != nil {
        return false
    }
    packet: string = fmt.tprintf("%d:%s", len(body), string(body))
    _, send_error := net.send_tcp(connection.socket, transmute([]byte)packet)
    return send_error == nil
}

// Sends a request and waits for the packet that comes from the same actor and is not an announcement (those have a "type" key)
@(private)
RdpRequest :: proc(connection: ^RdpConnection, actor, type: string, extra_key := "", extra_value := "") -> (reply: json.Object, ok: bool) {
    if !RdpSend(connection, actor, type, extra_key, extra_value) {
        return
    }
    for {
        text, received := RdpReceive(connection)
        if !received {
            return
        }
        value, error := json.parse(transmute([]byte)text, allocator = context.temp_allocator)
        RdpConsume(connection, text)
        if error != nil {
            return
        }
        object, is_object := value.(json.Object)
        if !is_object {
            continue
        }
        from, _ := object["from"].(json.String)
        if string(from) == actor && "type" not_in object {
            return object, true
        }
    }
}

// Start Firefox when no debugger answers on the port, then install the folder as a temporary add-on
FirefoxInstall :: proc(executable, profile, directory: string, options: InstallOptions) -> bool {
    port: int = options.debugger_port if options.debugger_port != 0 else DEFAULT_DEBUGGER_PORT
    connection: ^RdpConnection = new(RdpConnection, context.temp_allocator)

    // a Firefox of an earlier run keeps the profile locked: reuse it, that reloads the add-on
    connected: bool = RdpConnect(connection, port)
    if !connected {
        if os.write_entire_file(fmt.tprintf("%s/user.js", profile), FIREFOX_USER_PREFS) != nil {
            fmt.eprintfln("browser_extension: could not write user.js in %s", profile)
            return false
        }
        command: [dynamic]string
        command.allocator = context.temp_allocator
        append(&command, executable, "-profile", profile, "-no-remote", "-start-debugger-server", fmt.tprintf("%d", port))
        if options.headless {
            append(&command, "-headless")
        }
        _, start_error := os.process_start({command = command[:]})
        if start_error != nil {
            fmt.eprintfln("browser_extension: could not start %s", executable)
            return false
        }

        start: time.Time = time.now()
        for !connected && time.since(start) < RDP_CONNECT_TIMEOUT {
            time.sleep(250 * time.Millisecond)
            connected = RdpConnect(connection, port)
        }
        if !connected {
            fmt.eprintfln("browser_extension: Firefox did not open the debugging port %d", port)
            return false
        }
    }
    defer net.close(connection.socket)

    // the greeting of the server
    greeting, greeted := RdpReceive(connection)
    if !greeted {
        fmt.eprintln("browser_extension: the debugging server sent no greeting")
        return false
    }
    RdpConsume(connection, greeting)
    return FirefoxInstallAddon(connection, directory)
}

@(private)
FirefoxInstallAddon :: proc(connection: ^RdpConnection, directory: string) -> bool {
    root, root_ok := RdpRequest(connection, "root", "getRoot")
    if !root_ok {
        fmt.eprintln("browser_extension: no answer to getRoot")
        return false
    }
    addons, has_addons := root["addonsActor"].(json.String)
    if !has_addons {
        fmt.eprintln("browser_extension: this Firefox has no addons actor")
        return false
    }
    result, installed := RdpRequest(connection, string(addons), "installTemporaryAddon", "addonPath", directory)
    if !installed {
        fmt.eprintln("browser_extension: no answer to installTemporaryAddon")
        return false
    }
    if message, failed := result["error"].(json.String); failed {
        details, _ := result["message"].(json.String)
        fmt.eprintfln("browser_extension: Firefox refused the add-on: %s %s", string(message), string(details))
        return false
    }
    addon, has_addon := result["addon"].(json.Object)
    if !has_addon {
        fmt.eprintln("browser_extension: Firefox answered without an add-on")
        return false
    }
    id, _ := addon["id"].(json.String)
    fmt.printfln("Firefox installed the temporary add-on %s", string(id))
    return true
}

// --- Tests ---

@(test)
test_rdp_packets :: proc(t: ^testing.T) {
    connection: ^RdpConnection = new(RdpConnection, context.temp_allocator)
    first: string = `{"from":"root"}`
    second: string = `{"a":1}`
    packets: string = fmt.tprintf("%d:%s%d:%s", len(first), first, len(second), second)
    copy(connection.buffer[:], packets)
    connection.filled = len(packets)

    // both packets are in the buffer already, so no socket is read
    text, ok := RdpReceive(connection)
    testing.expect(t, ok)
    testing.expect_value(t, text, first)
    RdpConsume(connection, text)
    text, ok = RdpReceive(connection)
    testing.expect(t, ok)
    testing.expect_value(t, text, second)
    RdpConsume(connection, text)
    testing.expect_value(t, connection.filled, 0)
}
