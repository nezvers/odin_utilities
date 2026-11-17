#+build !js
// Wire format of the messages that travel over a p2p Link. Every message is a frame: [kind u8][from u8][to u8][body].
// `from` and `to` are member ids (the host is 0, guests get 1..8 from the host, ALL means everybody), so a guest talks to another
// guest through the host, which checks `from` against the link the frame came in on (nobody can speak as somebody else).
// Pure functions over caller buffers (serial.Writer / Reader), nothing allocated.
package ai_messaging

import "core:testing"
import p2p "../p2p"
import serial "../serial"

HOST_ID :: u8(0)
ALL :: u8(255)
UNKNOWN_ID :: u8(254)                   // a guest before the host told it its id
MAX_MEMBERS :: p2p.MAX_PEERS + 1
NAME_MAX :: p2p.NAME_MAX
FRAME_HEADER :: 3
MAX_TEXT :: 800
FILE_CHUNK :: 800                       // file bytes in one chunk frame (frame + chunk header stay under p2p.MAX_PAYLOAD)
FILE_NAME_MAX :: 120
HASH_SIZE :: 32

Kind :: enum u8 {
    NONE,
    ROSTER,                             // host to a guest: [count u8]{[id u8][name]}, `to` is the receiver's own id
    TEXT,                               // [text]
    FILE_OFFER,                         // [transfer u16][size u64][name]
    FILE_ACCEPT,                        // [transfer u16]
    FILE_REJECT,                        // [transfer u16][reason]
    FILE_CHUNK,                         // [transfer u16][offset u64][bytes...]
    FILE_CREDIT,                        // [transfer u16][bytes received u64]: the sender may go on up to this + the window
    FILE_END,                           // [transfer u16][sha256 32]
    FILE_DONE,                          // [transfer u16][ok bool][message]: the receiver's verdict
}

Frame :: struct {
    kind: Kind,
    from: u8,
    to: u8,
    body: serial.Reader,
}

// Starts a frame in `buffer`; the caller appends the body with serial.Write* and finishes with serial.WriterBytes.
FrameBegin :: proc(writer: ^serial.Writer, buffer: []byte, kind: Kind, from: u8, to: u8) {
    serial.WriterInit(writer, buffer)
    serial.WriteU8(writer, u8(kind))
    serial.WriteU8(writer, from)
    serial.WriteU8(writer, to)
}

FrameParse :: proc(data: []byte) -> (frame: Frame, ok: bool) {
    if len(data) < FRAME_HEADER || data[0] == 0 || data[0] > u8(max(Kind)) {
        return
    }
    frame.kind = Kind(data[0])
    frame.from = data[1]
    frame.to = data[2]
    serial.ReaderInit(&frame.body, data[FRAME_HEADER:])
    return frame, true
}

@(test)
FrameTest :: proc(t: ^testing.T) {
    buffer: [p2p.MAX_PAYLOAD]byte
    writer: serial.Writer
    FrameBegin(&writer, buffer[:], .FILE_OFFER, 3, 5)
    serial.WriteU16(&writer, 7)
    serial.WriteU64(&writer, 1 << 40)
    serial.WriteString(&writer, "notes.txt")
    testing.expect(t, serial.WriterOk(&writer))

    frame, ok := FrameParse(serial.WriterBytes(&writer))
    testing.expect(t, ok)
    testing.expect_value(t, frame.kind, Kind.FILE_OFFER)
    testing.expect_value(t, frame.from, u8(3))
    testing.expect_value(t, frame.to, u8(5))
    testing.expect_value(t, serial.ReadU16(&frame.body), u16(7))
    testing.expect_value(t, serial.ReadU64(&frame.body), u64(1 << 40))
    testing.expect_value(t, serial.ReadString(&frame.body), "notes.txt")
    testing.expect(t, serial.ReaderOk(&frame.body))

    // garbage never parses: too short, kind 0, a kind that does not exist
    short: [2]byte = {1, 2}
    _, ok = FrameParse(short[:])
    testing.expect(t, !ok)
    zero: [3]byte = {0, 0, 0}
    _, ok = FrameParse(zero[:])
    testing.expect(t, !ok)
    unknown: [3]byte = {200, 0, 0}
    _, ok = FrameParse(unknown[:])
    testing.expect(t, !ok)

    // a cut body is noticed by the reader, not by a crash
    frame, ok = FrameParse(serial.WriterBytes(&writer)[:FRAME_HEADER + 4])
    testing.expect(t, ok)
    serial.ReadU16(&frame.body)
    serial.ReadU64(&frame.body)
    testing.expect(t, !serial.ReaderOk(&frame.body))
}
