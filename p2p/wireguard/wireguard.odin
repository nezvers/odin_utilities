// Optional encrypted tunnel for p2p: WireGuard, installed on request, configured from the data the two sides already exchanged.
//
// What it is for: the p2p Link has no encryption. WireGuard adds it (Curve25519, ChaCha20-Poly1305) and a virtual LAN (each side gets
// a 10.x address, any program can talk over it). What it is NOT: a relay. The tunnel travels over the same UDP path the p2p punch found,
// so it does not get through a NAT that the punch could not. That is why the keys are exchanged over the already connected Link and the
// tunnel then takes over the same port (the NAT mapping stays, only the program owning the port changes).
//
// This package changes the computer (installs software, adds a network interface, needs administrator rights), so:
//  - nothing here runs by itself: the caller asks `Describe` first, shows it to the person and only then calls `Install` / `Up`;
//  - every step is reported to the `Log` procedure BEFORE it is done, with the exact command line;
//  - on Windows the official installer is downloaded from download.wireguard.com and its signature is checked before it runs;
//    on Linux the system package manager installs `wireguard-tools` (the kernel has had WireGuard since 5.6).
// Keys are made here with core:crypto (no `wg genkey` needed). macOS is not supported (the userspace tools need extra setup).
package wireguard

import "core:crypto"
import "core:crypto/x25519"
import "core:encoding/base64"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

TUNNEL_NAME :: "p2pchat"                        // interface (Linux) / service (Windows) name, <= 15 characters
HOST_ADDRESS :: "10.73.82.1"                    // the virtual LAN: one side is .1, the other .2
GUEST_ADDRESS :: "10.73.82.2"
KEEPALIVE_SECONDS :: 1                          // both sides send at once: that is what keeps the NAT hole open and starts the handshake
KEY_TEXT_LENGTH :: 44                           // base64 of 32 bytes
WINDOWS_INSTALLER_URL :: "https://download.wireguard.com/windows-client/wireguard-installer.exe"
WINDOWS_PROGRAM :: `C:\Program Files\WireGuard\wireguard.exe`
WINDOWS_SIGNER :: "WireGuard LLC"
CONFIG_MAX :: 512

// Every step is reported here before it happens (the chat prints them as "[wireguard] ...").
Log :: #type proc(message: string)

Platform :: enum {
    UNSUPPORTED,
    WINDOWS,
    LINUX,
}

PackageManager :: enum {
    NONE,
    APT,
    DNF,
    YUM,
    PACMAN,
    ZYPPER,
    APK,
}

KeyPair :: struct {
    private: [32]byte,
    public: [32]byte,
}

CurrentPlatform :: proc() -> Platform {
    when ODIN_OS == .Windows {
        return .WINDOWS
    } else when ODIN_OS == .Linux {
        return .LINUX
    } else {
        return .UNSUPPORTED
    }
}

// ---------------------------------------------------------------------------------------------------------------- keys

// A new random key pair. The private key is clamped like `wg genkey` does (the format WireGuard expects in a config file).
KeyGenerate :: proc(pair: ^KeyPair) -> bool {
    if !crypto.HAS_RAND_BYTES {
        return false
    }
    crypto.rand_bytes(pair.private[:])
    pair.private[0] &= 248
    pair.private[31] &= 127
    pair.private[31] |= 64
    x25519.scalarmult_basepoint(pair.public[:], pair.private[:])
    return true
}

// Standard base64 with padding, 44 characters: the form in config files and in what the two sides exchange.
KeyText :: proc(key: [32]byte, buffer: []byte) -> string {
    assert(len(buffer) >= KEY_TEXT_LENGTH)
    key_copy: [32]byte = key
    encoded, error := base64.encode_into_buf(buffer, key_copy[:])
    if error != nil {
        return ""
    }
    return string(encoded)
}

KeyFromText :: proc(text: string) -> (key: [32]byte, ok: bool) {
    if len(text) != KEY_TEXT_LENGTH {
        return {}, false
    }
    decoded, error := base64.decode_into_buf(key[:], text)
    if error != nil || len(decoded) != 32 {
        return {}, false
    }
    return key, true
}

// ------------------------------------------------------------------------------------------------------------- config

// The tunnel's configuration file. `endpoint` is the address the p2p punch found working for the peer; `listen_port` is the
// port the Link had (the NAT mapping belongs to it). Written into the caller's buffer, no allocation.
ConfigWrite :: proc(buffer: []byte, private: [32]byte, own_address: string, listen_port: int, peer_public: [32]byte, peer_address: string, endpoint: string) -> string {
    private_text: [KEY_TEXT_LENGTH]byte
    public_text: [KEY_TEXT_LENGTH]byte
    text: string = fmt.bprintf(
        buffer,
        "[Interface]\nPrivateKey = %s\nAddress = %s/24\nListenPort = %d\n\n[Peer]\nPublicKey = %s\nAllowedIPs = %s/32\nEndpoint = %s\nPersistentKeepalive = %d\n",
        KeyText(private, private_text[:]), own_address, listen_port, KeyText(peer_public, public_text[:]), peer_address, endpoint, KEEPALIVE_SECONDS,
    )
    return text
}

// ------------------------------------------------------------------------------------------------------------ install

Installed :: proc() -> bool {
    switch CurrentPlatform() {
    case .WINDOWS:
        return os.exists(WINDOWS_PROGRAM)
    case .LINUX:
        return FindTool("wg-quick") != "" && FindTool("wg") != ""
    case .UNSUPPORTED:
    }
    return false
}

// Tools are looked for in the usual places instead of walking PATH: sudo often runs with a cut down PATH, so full paths are used.
FindTool :: proc(name: string) -> string {
    folders: [6]string = {"/usr/bin", "/usr/sbin", "/usr/local/bin", "/usr/local/sbin", "/bin", "/sbin"}
    for folder in folders {
        path: string = fmt.tprintf("%s/%s", folder, name)
        if os.exists(path) {
            return path
        }
    }
    return ""
}

PackageManagerFind :: proc(has: proc(name: string) -> bool) -> PackageManager {
    switch {
    case has("apt-get"):
        return .APT
    case has("dnf"):
        return .DNF
    case has("yum"):
        return .YUM
    case has("pacman"):
        return .PACMAN
    case has("zypper"):
        return .ZYPPER
    case has("apk"):
        return .APK
    }
    return .NONE
}

HasTool :: proc(name: string) -> bool {
    return FindTool(name) != ""
}

// Package manager commands (run with sudo). Globals so the returned slices stay valid.
COMMAND_APT := [?]string{"apt-get", "install", "-y", "wireguard-tools"}
COMMAND_DNF := [?]string{"dnf", "install", "-y", "wireguard-tools"}
COMMAND_YUM := [?]string{"yum", "install", "-y", "wireguard-tools"}
COMMAND_PACMAN := [?]string{"pacman", "-S", "--noconfirm", "wireguard-tools"}
COMMAND_ZYPPER := [?]string{"zypper", "--non-interactive", "install", "wireguard-tools"}
COMMAND_APK := [?]string{"apk", "add", "wireguard-tools"}

PackageCommand :: proc(manager: PackageManager) -> []string {
    switch manager {
    case .APT:
        return COMMAND_APT[:]
    case .DNF:
        return COMMAND_DNF[:]
    case .YUM:
        return COMMAND_YUM[:]
    case .PACMAN:
        return COMMAND_PACMAN[:]
    case .ZYPPER:
        return COMMAND_ZYPPER[:]
    case .APK:
        return COMMAND_APK[:]
    case .NONE:
    }
    return nil
}

// Plain words for the person, shown BEFORE anything is installed or started. Uses the temp allocator.
Describe :: proc() -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    switch CurrentPlatform() {
    case .WINDOWS:
        strings.write_string(&builder, "WireGuard adds an encrypted tunnel between the two computers (the chat itself has no encryption).\n")
        if Installed() {
            strings.write_string(&builder, "WireGuard is already installed. It will only add a temporary tunnel named " + TUNNEL_NAME + " (a Windows service) and remove it at the end.\n")
        } else {
            strings.write_string(&builder, "WireGuard is not installed. What will happen:\n")
            strings.write_string(&builder, "  1. the official installer is downloaded from " + WINDOWS_INSTALLER_URL + " to your temp folder\n")
            strings.write_string(&builder, "  2. its digital signature is checked (it must be signed by \"" + WINDOWS_SIGNER + "\"), otherwise nothing is run\n")
            strings.write_string(&builder, "  3. the installer is started with administrator rights (Windows asks you to allow it) and installs WireGuard\n")
        }
        strings.write_string(&builder, "Later the tunnel is created with administrator rights (another Windows prompt) and removed when you leave the chat.\n")
    case .LINUX:
        strings.write_string(&builder, "WireGuard adds an encrypted tunnel between the two computers (the chat itself has no encryption).\n")
        if Installed() {
            strings.write_string(&builder, "WireGuard tools are already installed. It will only add a temporary interface named " + TUNNEL_NAME + " with sudo and remove it at the end.\n")
        } else {
            manager: PackageManager = PackageManagerFind(HasTool)
            command: []string = PackageCommand(manager)
            if command == nil {
                strings.write_string(&builder, "WireGuard tools are not installed and no known package manager was found: install the package \"wireguard-tools\" yourself.\n")
            } else {
                fmt.sbprintf(&builder, "WireGuard tools are not installed. They will be installed with your package manager: sudo %s\n", strings.join(command, " ", context.temp_allocator))
            }
        }
        strings.write_string(&builder, "The interface is created and removed with sudo (wg-quick); sudo may ask for your password in this terminal.\n")
    case .UNSUPPORTED:
        strings.write_string(&builder, "WireGuard setup is only supported on Windows and Linux.\n")
    }
    return strings.to_string(builder)
}

// Runs a command and reports it first. Returns the exit code (-1 when it could not even start) and its output (temp allocator).
@(private)
Run :: proc(log: Log, command: []string) -> (exit: int, output: string) {
    log(fmt.tprintf("$ %s", strings.join(command, " ", context.temp_allocator)))
    state, stdout, stderr, error := os.process_exec({command = command}, context.temp_allocator)
    if error != nil {
        log(fmt.tprintf("could not start %s: %v", command[0], error))
        return -1, ""
    }
    text: string = strings.trim_space(strings.concatenate({string(stdout), string(stderr)}, context.temp_allocator))
    return state.exit_code, text
}

// Same, but with the program's own terminal (sudo asks for the password there). Output is not captured.
@(private)
RunInteractive :: proc(log: Log, command: []string) -> int {
    log(fmt.tprintf("$ %s", strings.join(command, " ", context.temp_allocator)))
    process, start_error := os.process_start({command = command, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr})
    if start_error != nil {
        log(fmt.tprintf("could not start %s: %v", command[0], start_error))
        return -1
    }
    state, wait_error := os.process_wait(process)
    if wait_error != nil {
        return -1
    }
    return state.exit_code
}

// Windows: one PowerShell command that starts `program` elevated (the UAC prompt) and waits for it. The exit code of an
// elevated child is not passed back reliably, so callers check the result (Installed, TunnelRunning) instead.
@(private)
RunElevatedWindows :: proc(log: Log, program: string, arguments: string) -> bool {
    script: string = fmt.tprintf("Start-Process -FilePath '%s' -ArgumentList '%s' -Verb RunAs -Wait", program, arguments)
    exit: int
    output: string
    exit, output = Run(log, {"powershell", "-NoProfile", "-NonInteractive", "-Command", script})
    if exit != 0 {
        log(fmt.tprintf("not allowed or failed: %s", output))
    }
    return exit == 0
}

// Gets sudo ready ONCE, before the chat starts reading the keyboard (the password prompt needs the terminal).
SudoPrepare :: proc(log: Log) -> bool {
    if CurrentPlatform() != .LINUX {
        return true
    }
    log("asking sudo for permission (it may ask for your password; it is remembered for a few minutes)")
    return RunInteractive(log, {"sudo", "-v"}) == 0
}

// Installs the WireGuard tools when missing. Returns true when they are present afterwards.
Install :: proc(log: Log) -> bool {
    if Installed() {
        log("WireGuard is already installed, nothing to do")
        return true
    }
    switch CurrentPlatform() {
    case .WINDOWS:
        folder: string = WorkFolder()
        installer: string = fmt.tprintf(`%s\wireguard-installer.exe`, folder)
        log(fmt.tprintf("step 1/3: downloading the official installer to %s", installer))
        download: string = fmt.tprintf("$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%s' -OutFile '%s'", WINDOWS_INSTALLER_URL, installer)
        exit, output := Run(log, {"powershell", "-NoProfile", "-NonInteractive", "-Command", download})
        if exit != 0 {
            log(fmt.tprintf("download failed: %s", output))
            return false
        }
        log("step 2/3: checking the digital signature of the installer")
        check: string = fmt.tprintf("$s = Get-AuthenticodeSignature -FilePath '%s'; if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch '%s') { exit 3 }", installer, WINDOWS_SIGNER)
        exit, output = Run(log, {"powershell", "-NoProfile", "-NonInteractive", "-Command", check})
        if exit != 0 {
            log("the installer is NOT signed by " + WINDOWS_SIGNER + ", it is deleted and not run")
            os.remove(installer)
            return false
        }
        log("signature is valid")
        log("step 3/3: running the installer with administrator rights (allow it in the Windows prompt, it takes up to a minute)")
        RunElevatedWindows(log, installer, "")
        os.remove(installer)
    case .LINUX:
        command: []string = PackageCommand(PackageManagerFind(HasTool))
        if command == nil {
            log("no known package manager: install the package \"wireguard-tools\" yourself")
            return false
        }
        log("installing the WireGuard tools with the package manager")
        full: [8]string
        full[0] = "sudo"
        for part, i in command {
            full[i + 1] = part
        }
        if RunInteractive(log, full[:len(command) + 1]) != 0 {
            log("the package manager failed")
            return false
        }
    case .UNSUPPORTED:
        log("unsupported system")
        return false
    }
    installed: bool = Installed()
    log("WireGuard is now installed" if installed else "WireGuard is still not installed")
    return installed
}

// ---------------------------------------------------------------------------------------------------------------- tunnel

@(private)
WorkFolder :: proc() -> string {
    base, error := os.temp_directory(context.temp_allocator)
    if error != nil {
        return "."
    }
    folder: string = fmt.tprintf("%s/p2p_wireguard", strings.trim_right(base, "/\\"))
    os.make_directory(folder)
    return folder
}

// Creates the tunnel from a config text (see ConfigWrite). The config file holds the private key: it is written to a private
// folder and deleted right after the tunnel took it over.
Up :: proc(log: Log, config: string) -> bool {
    folder: string = WorkFolder()
    path: string
    switch CurrentPlatform() {
    case .WINDOWS:
        path = fmt.tprintf(`%s\%s.conf`, folder, TUNNEL_NAME)
    case .LINUX:
        path = fmt.tprintf("%s/%s.conf", folder, TUNNEL_NAME)
    case .UNSUPPORTED:
        log("unsupported system")
        return false
    }
    log(fmt.tprintf("writing the tunnel configuration (contains the private key) to %s, it is deleted right after", path))
    if os.write_entire_file(path, config, os.Permissions{.Read_User, .Write_User}) != nil {
        log("could not write the configuration")
        return false
    }
    defer os.remove(path)

    if CurrentPlatform() == .WINDOWS {
        log("creating the tunnel service (allow it in the Windows prompt)")
        RunElevatedWindows(log, WINDOWS_PROGRAM, fmt.tprintf("/installtunnelservice \"%s\"", path))
    } else {
        log("bringing the interface up with wg-quick")
        exit, output := Run(log, {"sudo", "-n", FindTool("wg-quick"), "up", path})
        if exit != 0 {
            log(fmt.tprintf("wg-quick failed: %s", output))
        }
    }
    running: bool = TunnelRunning()
    log("tunnel is up" if running else "tunnel did not start")
    return running
}

Down :: proc(log: Log) {
    if !TunnelRunning() {
        return
    }
    switch CurrentPlatform() {
    case .WINDOWS:
        log("removing the tunnel service (allow it in the Windows prompt)")
        RunElevatedWindows(log, WINDOWS_PROGRAM, "/uninstalltunnelservice " + TUNNEL_NAME)
    case .LINUX:
        log("removing the interface")
        // wg-quick down wants the config file it started from; the interface name works too when the file is gone
        Run(log, {"sudo", "-n", FindTool("ip"), "link", "delete", TUNNEL_NAME})
    case .UNSUPPORTED:
    }
    log("tunnel removed" if !TunnelRunning() else "the tunnel is still there, remove it by hand")
}

TunnelRunning :: proc() -> bool {
    quiet: Log = proc(message: string) {}
    switch CurrentPlatform() {
    case .WINDOWS:
        _, output := Run(quiet, {"sc", "query", "WireGuardTunnel$" + TUNNEL_NAME})
        return strings.contains(output, "RUNNING")
    case .LINUX:
        exit, _ := Run(quiet, {FindTool("ip"), "link", "show", TUNNEL_NAME})
        return exit == 0
    case .UNSUPPORTED:
    }
    return false
}

// ---------------------------------------------------------------------------------------------------------------- tests

// RFC 7748 section 6.1: the public key of the example private key. Proves the key derivation is the standard one (it is what
// a real WireGuard peer computes), independent of the clamping done in KeyGenerate.
@(test)
KeyDerivationTest :: proc(t: ^testing.T) {
    private: [32]byte = {
        0x77, 0x07, 0x6d, 0x0a, 0x73, 0x18, 0xa5, 0x7d, 0x3c, 0x16, 0xc1, 0x72, 0x51, 0xb2, 0x66, 0x45,
        0xdf, 0x4c, 0x2f, 0x87, 0xeb, 0xc0, 0x99, 0x2a, 0xb1, 0x77, 0xfb, 0xa5, 0x1d, 0xb9, 0x2c, 0x2a,
    }
    expected: [32]byte = {
        0x85, 0x20, 0xf0, 0x09, 0x89, 0x30, 0xa7, 0x54, 0x74, 0x8b, 0x7d, 0xdc, 0xb4, 0x3e, 0xf7, 0x5a,
        0x0d, 0xbf, 0x3a, 0x0d, 0x26, 0x38, 0x1a, 0xf4, 0xeb, 0xa4, 0xa9, 0x8e, 0xaa, 0x9b, 0x4e, 0x6a,
    }
    public: [32]byte
    x25519.scalarmult_basepoint(public[:], private[:])
    testing.expect_value(t, public, expected)

    pair: KeyPair
    testing.expect(t, KeyGenerate(&pair))
    testing.expect_value(t, pair.private[0] & 7, u8(0))
    testing.expect_value(t, pair.private[31] & 0xC0, u8(0x40))
    again: [32]byte
    x25519.scalarmult_basepoint(again[:], pair.private[:])
    testing.expect_value(t, again, pair.public)
}

@(test)
KeyTextTest :: proc(t: ^testing.T) {
    pair: KeyPair
    testing.expect(t, KeyGenerate(&pair))
    text: [KEY_TEXT_LENGTH]byte
    encoded: string = KeyText(pair.public, text[:])
    testing.expect_value(t, len(encoded), KEY_TEXT_LENGTH)
    back, ok := KeyFromText(encoded)
    testing.expect(t, ok)
    testing.expect_value(t, back, pair.public)
    _, bad := KeyFromText("too short")
    testing.expect(t, !bad)
    // a known WireGuard key from the wg-quick(8) examples shape: all zero bytes encode to 43 'A' and a '='
    zero: [32]byte
    testing.expect_value(t, KeyText(zero, text[:]), "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
}

@(test)
ConfigTest :: proc(t: ^testing.T) {
    private: [32]byte
    peer: [32]byte
    private[0] = 1
    buffer: [CONFIG_MAX]byte
    text: string = ConfigWrite(buffer[:], private, HOST_ADDRESS, 51820, peer, GUEST_ADDRESS, "203.0.113.7:40000")
    testing.expect(t, strings.has_prefix(text, "[Interface]\nPrivateKey = AQAAAAAA"))
    testing.expect(t, strings.contains(text, "Address = 10.73.82.1/24\nListenPort = 51820\n"))
    testing.expect(t, strings.contains(text, "AllowedIPs = 10.73.82.2/32\nEndpoint = 203.0.113.7:40000\nPersistentKeepalive = 1\n"))
    testing.expect(t, len(text) < CONFIG_MAX)
}

@(test)
PackageManagerTest :: proc(t: ^testing.T) {
    testing.expect_value(t, PackageManagerFind(proc(name: string) -> bool { return name == "apt-get" || name == "dnf" }), PackageManager.APT)
    testing.expect_value(t, PackageManagerFind(proc(name: string) -> bool { return name == "pacman" }), PackageManager.PACMAN)
    testing.expect_value(t, PackageManagerFind(proc(name: string) -> bool { return false }), PackageManager.NONE)
    testing.expect(t, PackageCommand(.NONE) == nil)
    testing.expect_value(t, PackageCommand(.APT)[len(PackageCommand(.APT)) - 1], "wireguard-tools")
    testing.expect(t, len(Describe()) > 0)
}
