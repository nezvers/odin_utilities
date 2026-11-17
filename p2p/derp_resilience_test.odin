package p2p

import "core:testing"

@(test)
DerpHostAndHttpTest :: proc(t: ^testing.T) {
    host, port := DerpSplitHost("derp.example.com")
    testing.expect_value(t, host, "derp.example.com")
    testing.expect_value(t, port, 443)
    host, port = DerpSplitHost("derp.example.com:8443")
    testing.expect_value(t, host, "derp.example.com")
    testing.expect_value(t, port, 8443)
    host, port = DerpSplitHost("derp.example.com:")
    testing.expect_value(t, port, 443)
    host, port = DerpSplitHost("derp.example.com:99999")
    testing.expect_value(t, port, 443)
    testing.expect_value(t, DerpHttpStatus(transmute([]byte)string("HTTP/1.1 101 Switching Protocols\r\n")), 101)
    testing.expect_value(t, DerpHttpStatus(transmute([]byte)string("HTTP/1.1 302 Found\r\nLocation: x\r\n\r\n")), 302)
    testing.expect_value(t, DerpHttpStatus(transmute([]byte)string("HTTP/2 404 \r\n\r\n")), 404)
    testing.expect_value(t, DerpHttpStatus(transmute([]byte)string("not http at all")), 0)
    // every failure has advice that says what to do, except "none"
    for kind in DerpFailure {
        testing.expect_value(t, len(DerpAdvice(kind)) > 0, kind != .NONE)
    }
}

// A relay that is not in the built in list travels in the code by name; both sides must name the same one.
@(test)
DerpCustomRelayTest :: proc(t: ^testing.T) {
    invite: Invite = {kind = .INVITE, session = 5, id = 6, derp_server = DERP_CUSTOM}
    host: string = "derp.example.com:8443"
    invite.derp_host_length = len(host)
    copy(invite.derp_host[:], host)
    invite.derp_key[0] = 7
    buffer: [CODE_TEXT_MAX]byte
    text, ok := InviteEncode(invite, buffer[:])
    testing.expect(t, ok)
    decoded, decoded_ok := InviteDecode(text)
    testing.expect(t, decoded_ok && decoded == invite)
    testing.expect_value(t, InviteDerpHost(&decoded), host)

    path: DerpPath = {server = DERP_CUSTOM, host_length = len(host)}
    copy(path.host[:], host)
    testing.expect(t, DerpSameRelay(&path, invite))
    other: Invite = invite
    other.derp_host[0] = 'x'
    testing.expect(t, !DerpSameRelay(&path, other))                  // another relay
    builtin: Invite = {derp_server = 3}
    testing.expect(t, !DerpSameRelay(&path, builtin))
    path.server = 3
    testing.expect(t, DerpSameRelay(&path, builtin))
    testing.expect_value(t, InviteDerpHost(&builtin), DERP_SERVERS[2].host)

    // a custom invite without a name, or with a name that is too long, is refused
    invite.derp_host_length = 0
    text, ok = InviteEncode(invite, buffer[:])
    testing.expect(t, ok)
    _, decoded_ok = InviteDecode(text)
    testing.expect(t, !decoded_ok)
}
