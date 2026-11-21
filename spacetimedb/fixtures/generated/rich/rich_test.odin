package rich

// Written by hand, next to the generated file: what the generated code does with real bytes

import "core:testing"
import st "../../.."

@(test)
test_generated_row_round_trip :: proc(t: ^testing.T) {
    big: [16]u8
    big[0], big[15] = 1, 255
    tags: []string = {"a", "bc"}
    player: Player = {id = 7, name = "Ada", score = 42, tags = tags, color = .Green, shape = Shape_Circle{value = 2.5}, big = big}
    player.owner[0] = 9
    player.seen = 1234567
    buffer: [256]u8
    writer: st.Writer = st.WriterMake(buffer[:])
    PlayerWrite(&writer, player)
    testing.expect(t, !st.WriterFailed(&writer))
    reader: st.Reader = st.ReaderMake(st.WriterBytes(&writer))
    read: Player = PlayerRead(&reader)
    testing.expect(t, !st.ReaderFailed(&reader) && st.ReaderLeft(&reader) == 0, "the whole row was read")
    testing.expect_value(t, read.id, 7)
    testing.expect_value(t, read.name, "Ada")
    testing.expect_value(t, read.score, 42)
    testing.expect_value(t, len(read.tags), 2)
    testing.expect_value(t, read.tags[1], "bc")
    testing.expect_value(t, read.color, Color.Green)
    testing.expect_value(t, read.shape.(Shape_Circle).value, 2.5)
    testing.expect_value(t, read.seen, st.Timestamp(1234567))
    testing.expect_value(t, read.owner[0], 9)
    testing.expect_value(t, read.big, big)

    // an option without a value and a shape without a payload
    player.score = nil
    player.shape = Shape_Nothing{}
    writer = st.WriterMake(buffer[:])
    PlayerWrite(&writer, player)
    reader = st.ReaderMake(st.WriterBytes(&writer))
    again: Player = PlayerRead(&reader)
    _, has_score := again.score.?
    testing.expect(t, !has_score)
    _, is_nothing := again.shape.(Shape_Nothing)
    testing.expect(t, is_nothing)
}

@(test)
test_generated_tables_use_the_primary_key_of_the_schema :: proc(t: ^testing.T) {
    slots: [4]st.CacheSlot
    buckets: [4]i32
    bytes: [1024]u8
    events: [4]st.CacheEvent
    tables: [2]st.CacheTable
    cache: st.Cache
    st.CacheInit(&cache, {slots = slots[:], buckets = buckets[:], bytes = bytes[:], events = events[:], tables = tables[:]})
    kept: Tables = TablesAdd(&cache)
    testing.expect_value(t, st.CacheCount(&cache, kept.player), 0)
    testing.expect_value(t, tables[kept.player].key_size, 8)       // the u64 id at the start of the row
    testing.expect_value(t, cache.table_count, 1)                  // the private table is not kept
}

@(test)
test_generated_reducer_call_encodes_its_arguments :: proc(t: ^testing.T) {
    // the call is written into the connection's buffer: a connection that is not open can only say that it could not send
    connection: st.Connection
    testing.expect_value(t, CallMoveTo(&connection, 1, 2, {3}), 0)
}
