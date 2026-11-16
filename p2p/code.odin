// Session codes: what two people copy and paste to find each other without a server.
//
// An Invite holds the candidate addresses of one side (where it can be reached), a random session and peer id, and a name.
// The host makes an INVITE, the guest pastes it and answers with a REPLY, the host pastes the reply. After that both sides
// send packets at the same time (see link.odin) and the NATs let them through.
//
// Text form: binary fields (serial Writer) + crc32, written in Crockford base32 (no I L O U, case free, dashes and spaces
// ignored when reading) so it survives chat apps, line wraps and being typed from a phone. No allocation: the caller gives
// the text buffer, the decoded Invite is plain data.
package p2p

import "core:hash"
import "core:net"
import "core:testing"
import serial "../serial"

INVITE_VERSION :: u8(1)
NAME_MAX :: 24
MAX_CANDIDATES :: 6
CODE_BINARY_MAX :: 1 + 1 + 8 + 4 + 1 + NAME_MAX + 1 + MAX_CANDIDATES * 6 + 4
CODE_TEXT_MAX :: (CODE_BINARY_MAX * 8 + 4) / 5 + CODE_BINARY_MAX     // characters plus the dashes between groups of 5

CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

InviteKind :: enum u8 {
    INVITE = 1,         // made by the host, pasted by the guest
    REPLY = 2,          // made by the guest, pasted by the host
}

Invite :: struct {
    kind: InviteKind,
    session: u64,                   // random, chosen by the host, the same in the whole session
    id: u32,                        // random, identifies the sender in punch packets (addresses can change, this does not)
    name: [NAME_MAX]byte,
    name_len: int,
    candidates: [MAX_CANDIDATES]net.Endpoint,
    candidate_count: int,
}

InviteSetName :: proc(invite: ^Invite, name: string) {
    invite.name_len = min(len(name), NAME_MAX)
    copy(invite.name[:invite.name_len], name)
}

InviteName :: proc(invite: ^Invite) -> string {
    return string(invite.name[:invite.name_len])
}

// Adds an IPv4 candidate. Duplicates and a full list are ignored (returns false).
InviteAddCandidate :: proc(invite: ^Invite, endpoint: net.Endpoint) -> bool {
    if _, is_ip4 := endpoint.address.(net.IP4_Address); !is_ip4 {
        return false
    }
    for i in 0 ..< invite.candidate_count {
        if invite.candidates[i] == endpoint {
            return false
        }
    }
    if invite.candidate_count >= MAX_CANDIDATES {
        return false
    }
    invite.candidates[invite.candidate_count] = endpoint
    invite.candidate_count += 1
    return true
}

// Writes the text code into `out` (CODE_TEXT_MAX is enough) and returns it as a view of `out`.
InviteEncode :: proc(invite: Invite, out: []byte) -> (text: string, ok: bool) {
    assert(len(out) >= CODE_TEXT_MAX)
    binary: [CODE_BINARY_MAX]byte
    writer: serial.Writer
    serial.WriterInit(&writer, binary[:])
    serial.WriteU8(&writer, INVITE_VERSION)
    serial.WriteU8(&writer, u8(invite.kind))
    serial.WriteU64(&writer, invite.session)
    serial.WriteU32(&writer, invite.id)
    serial.WriteU8(&writer, u8(invite.name_len))
    name: [NAME_MAX]byte = invite.name
    serial.WriteBytes(&writer, name[:invite.name_len])
    serial.WriteU8(&writer, u8(invite.candidate_count))
    for i in 0 ..< invite.candidate_count {
        address, is_ip4 := invite.candidates[i].address.(net.IP4_Address)
        if !is_ip4 {
            return
        }
        serial.WriteBytes(&writer, address[:])
        serial.WriteU16(&writer, u16(invite.candidates[i].port))
    }
    // the check catches a typo or a half copied code before any packet is sent
    serial.WriteU32(&writer, hash.crc32(binary[:writer.offset]))
    if !serial.WriterOk(&writer) {
        return
    }
    length: int = TextEncode(serial.WriterBytes(&writer), out)
    return string(out[:length]), true
}

// Reads a code the way people paste it: any case, with dashes, spaces, line breaks, I/L/O typed for 1/1/0.
InviteDecode :: proc(text: string) -> (invite: Invite, ok: bool) {
    binary: [CODE_BINARY_MAX + 8]byte
    length: int = TextDecode(text, binary[:]) or_return
    if length < 4 {
        return
    }
    body: []byte = binary[:length - 4]
    check: u32
    {
        reader: serial.Reader
        serial.ReaderInit(&reader, binary[length - 4:length])
        check = serial.ReadU32(&reader)
    }
    if check != hash.crc32(body) {
        return
    }

    reader: serial.Reader
    serial.ReaderInit(&reader, body)
    if serial.ReadU8(&reader) != INVITE_VERSION {
        return
    }
    invite.kind = InviteKind(serial.ReadU8(&reader))
    invite.session = serial.ReadU64(&reader)
    invite.id = serial.ReadU32(&reader)
    invite.name_len = int(serial.ReadU8(&reader))
    if invite.name_len > NAME_MAX {
        return
    }
    copy(invite.name[:], serial.ReadBytes(&reader, invite.name_len))
    count: int = int(serial.ReadU8(&reader))
    if count > MAX_CANDIDATES {
        return
    }
    for _ in 0 ..< count {
        address: [4]byte
        copy(address[:], serial.ReadBytes(&reader, 4))
        port: u16 = serial.ReadU16(&reader)
        InviteAddCandidate(&invite, {address = net.IP4_Address(address), port = int(port)})
    }
    if !serial.ReaderOk(&reader) || serial.ReaderRemaining(&reader) != 0 {
        return
    }
    if invite.kind != .INVITE && invite.kind != .REPLY || invite.candidate_count == 0 {
        return
    }
    return invite, true
}

// ============================================================ Crockford base32 text

// Bytes to text in groups of 5 characters separated by '-'. `out` needs CODE_TEXT_MAX when data is CODE_BINARY_MAX long.
TextEncode :: proc(data: []byte, out: []byte) -> int {
    length: int
    bits: u32
    bit_count: u32
    chars: int
    put :: proc(out: []byte, length: ^int, chars: ^int, value: u32) {
        if chars^ > 0 && chars^ % 5 == 0 {
            out[length^] = '-'
            length^ += 1
        }
        out[length^] = CODE_ALPHABET[value]
        length^ += 1
        chars^ += 1
    }
    for b in data {
        bits = bits << 8 | u32(b)
        bit_count += 8
        for bit_count >= 5 {
            put(out, &length, &chars, (bits >> (bit_count - 5)) & 31)
            bit_count -= 5
        }
    }
    if bit_count > 0 {
        put(out, &length, &chars, (bits << (5 - bit_count)) & 31)
    }
    return length
}

// Text to bytes. Fails on a character that is not part of the alphabet.
TextDecode :: proc(text: string, out: []byte) -> (length: int, ok: bool) {
    bits: u32
    bit_count: u32
    for i in 0 ..< len(text) {
        c: byte = text[i]
        value: int = -1
        switch c {
        case '-', ' ', '\n', '\r', '\t':
            continue
        case 'o', 'O':
            value = 0
        case 'i', 'I', 'l', 'L':
            value = 1
        case 'a' ..= 'z':
            c -= 'a' - 'A'
            fallthrough
        case:
            for j in 0 ..< len(CODE_ALPHABET) {
                if CODE_ALPHABET[j] == c {
                    value = j
                    break
                }
            }
        }
        if value < 0 {
            return
        }
        bits = bits << 5 | u32(value)
        bit_count += 5
        if bit_count >= 8 {
            if length >= len(out) {
                return
            }
            out[length] = byte(bits >> (bit_count - 8))
            length += 1
            bit_count -= 8
        }
    }
    return length, true
}

// ============================================================ tests

@(test)
InviteRoundTripTest :: proc(t: ^testing.T) {
    invite: Invite = {kind = .REPLY, session = 0x1122334455667788, id = 0xCAFEBABE}
    InviteSetName(&invite, "Ann the second")
    InviteAddCandidate(&invite, {address = net.IP4_Address{203, 0, 113, 9}, port = 54321})
    InviteAddCandidate(&invite, {address = net.IP4_Address{192, 168, 1, 20}, port = 40000})
    testing.expect(t, !InviteAddCandidate(&invite, invite.candidates[0]))

    buffer: [CODE_TEXT_MAX]byte
    text, ok := InviteEncode(invite, buffer[:])
    testing.expect(t, ok)

    decoded, decoded_ok := InviteDecode(text)
    testing.expect(t, decoded_ok)
    testing.expect(t, decoded == invite)
    testing.expect_value(t, InviteName(&decoded), "Ann the second")

    // pasted the way a chat app mangles it: lower case, spaces, a line break, I for 1
    mangled: [CODE_TEXT_MAX + 8]byte
    count: int
    for i in 0 ..< len(text) {
        c: byte = text[i]
        if c == '-' {
            mangled[count] = ' '
            count += 1
            continue
        }
        if c == '1' {
            c = 'I'
        } else if c >= 'A' && c <= 'Z' {
            c += 'a' - 'A'
        }
        mangled[count] = c
        count += 1
    }
    mangled[count] = '\n'
    count += 1
    again, again_ok := InviteDecode(string(mangled[:count]))
    testing.expect(t, again_ok)
    testing.expect(t, again == invite)
}

@(test)
InviteRejectsDamageTest :: proc(t: ^testing.T) {
    invite: Invite = {kind = .INVITE, session = 7, id = 9}
    InviteAddCandidate(&invite, {address = net.IP4_Address{10, 0, 0, 1}, port = 1000})
    buffer: [CODE_TEXT_MAX]byte
    text, _ := InviteEncode(invite, buffer[:])

    // one changed character: the crc must catch it
    damaged: [CODE_TEXT_MAX]byte
    copy(damaged[:], text)
    damaged[3] = 'Z' if damaged[3] != 'Z' else 'Y'
    _, damaged_ok := InviteDecode(string(damaged[:len(text)]))
    testing.expect(t, !damaged_ok)

    _, cut_ok := InviteDecode(text[:len(text) / 2])
    testing.expect(t, !cut_ok)
    _, bad_ok := InviteDecode("hello world!")
    testing.expect(t, !bad_ok)
    _, empty_ok := InviteDecode("")
    testing.expect(t, !empty_ok)
}
