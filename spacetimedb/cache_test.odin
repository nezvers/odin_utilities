#+build !js
package spacetimedb

import "core:testing"

// A row of the test table: a u64 id (the key) and a u32 score, 12 bytes
@(private = "file")
testRow :: proc(id: u64, score: u32) -> [12]u8 {
    row: [12]u8
    writer: Writer = WriterMake(row[:])
    WriteU64(&writer, id)
    WriteU32(&writer, score)
    return row
}

@(private = "file")
Score :: struct {
    id: u64,
    score: u32,
}

@(private = "file")
scoreRead :: proc(reader: ^Reader) -> Score {
    return {id = ReadU64(reader), score = ReadU32(reader)}
}

@(private = "file")
testList :: proc(rows: [][12]u8) -> RowList {
    return {fixed_size = 12, data = (cast([^]u8)raw_data(rows))[:len(rows) * 12]}
}

@(private = "file")
TestCache :: struct {
    cache: Cache,
    slots: [8]CacheSlot,
    buckets: [4]i32,
    bytes: [256]u8,
    events: [16]CacheEvent,
    tables: [2]CacheTable,
}

@(private = "file")
testCacheMake :: proc(test: ^TestCache) -> (cache: ^Cache, scores: int) {
    CacheInit(&test.cache, {slots = test.slots[:], buckets = test.buckets[:], bytes = test.bytes[:], events = test.events[:], tables = test.tables[:]})
    return &test.cache, CacheTableAdd(&test.cache, "scores", 8)
}

@(private = "file")
testUpdate :: proc(inserts: [][12]u8, deletes: [][12]u8, tables: []TableUpdate, sets: []QuerySetUpdate) -> TransactionUpdate {
    tables[0] = {table = "scores", inserts = testList(inserts), deletes = testList(deletes)}
    sets[0] = {query_set_id = 1, tables = tables[:1]}
    return {query_sets = sets[:1]}
}

@(test)
test_cache_keeps_the_rows_of_a_subscription_and_their_changes :: proc(t: ^testing.T) {
    test: TestCache
    cache, scores := testCacheMake(&test)
    applied_rows: [][12]u8 = {testRow(1, 10), testRow(2, 20)}
    tables: [1]TableRows = {{table = "scores", rows = testList(applied_rows)}}
    CacheApply(cache, SubscribeApplied{query_set_id = 1, rows = {tables = tables[:]}})
    testing.expect_value(t, CacheCount(cache, scores), 2)
    testing.expect_value(t, len(CacheEvents(cache)), 2)
    testing.expect(t, CacheEvents(cache)[0].kind == .INSERT)

    key: [8]u8
    writer: Writer = WriterMake(key[:])
    WriteU64(&writer, 2)
    row, found := CacheFind(cache, scores, key[:])
    testing.expect(t, found)
    reader: Reader = ReaderMake(row)
    testing.expect_value(t, scoreRead(&reader), Score{2, 20})

    // an update: the same key deleted and inserted again with another score, a new row 3, and the row 1 deleted
    CacheClearEvents(cache)
    inserts: [][12]u8 = {testRow(2, 25), testRow(3, 30)}
    deletes: [][12]u8 = {testRow(2, 20), testRow(1, 10)}
    update_tables: [1]TableUpdate
    update_sets: [1]QuerySetUpdate
    CacheApply(cache, testUpdate(inserts, deletes, update_tables[:], update_sets[:]))
    testing.expect_value(t, CacheCount(cache, scores), 2)
    people: [4]Score
    collected: []Score = CacheCollect(cache, scores, scoreRead, people[:])
    testing.expect_value(t, len(collected), 2)
    sum: u32
    for s in collected { sum += s.score }
    testing.expect_value(t, sum, 55)           // 25 + 30
    kinds: [3]int
    for event in CacheEvents(cache) { kinds[int(event.kind)] += 1 }
    testing.expect_value(t, kinds, [3]int{1, 1, 1})      // an insert (3), an update (2), a delete (1)
    for event in CacheEvents(cache) {
        if event.kind == .UPDATE {
            old: Reader = ReaderMake(event.old)
            new: Reader = ReaderMake(event.row)
            testing.expect_value(t, scoreRead(&old).score, 20)
            testing.expect_value(t, scoreRead(&new).score, 25)
        }
    }
}

@(test)
test_cache_counts_references_of_a_row_that_two_subscriptions_match :: proc(t: ^testing.T) {
    test: TestCache
    cache, scores := testCacheMake(&test)
    rows: [][12]u8 = {testRow(7, 1)}
    tables: [1]TableRows = {{table = "scores", rows = testList(rows)}}
    CacheApply(cache, SubscribeApplied{query_set_id = 1, rows = {tables = tables[:]}})
    CacheApply(cache, SubscribeApplied{query_set_id = 2, rows = {tables = tables[:]}})
    testing.expect_value(t, CacheCount(cache, scores), 1)
    testing.expect_value(t, len(CacheEvents(cache)), 1)               // told once
    CacheApply(cache, UnsubscribeApplied{query_set_id = 1, has_rows = true, rows = {tables = tables[:]}})
    testing.expect_value(t, CacheCount(cache, scores), 1)             // the other subscription still has it
    CacheApply(cache, UnsubscribeApplied{query_set_id = 2, has_rows = true, rows = {tables = tables[:]}})
    testing.expect_value(t, CacheCount(cache, scores), 0)
    testing.expect_value(t, CacheEvents(cache)[1].kind, CacheEventKind.DELETE)
}

@(test)
test_cache_reuses_its_bytes_and_says_when_full :: proc(t: ^testing.T) {
    test: TestCache
    cache, scores := testCacheMake(&test)
    // 8 slots of 20 bytes in 256: add and remove 100 rows one after the other, the bytes are compacted when they run out
    for i in 0 ..< 100 {
        inserts: [][12]u8 = {testRow(u64(i), 1)}
        update_tables: [1]TableUpdate
        update_sets: [1]QuerySetUpdate
        CacheApply(cache, testUpdate(inserts, nil, update_tables[:], update_sets[:]))
        deletes: [][12]u8 = {testRow(u64(i), 1)}
        CacheApply(cache, testUpdate(nil, deletes, update_tables[:], update_sets[:]))
    }
    testing.expect(t, !cache.failed)
    testing.expect_value(t, CacheCount(cache, scores), 0)
    // nine rows do not fit eight slots
    many: [9][12]u8
    for i in 0 ..< 9 { many[i] = testRow(u64(i), 0) }
    update_tables: [1]TableUpdate
    update_sets: [1]QuerySetUpdate
    CacheApply(cache, testUpdate(many[:], nil, update_tables[:], update_sets[:]))
    testing.expect(t, cache.failed)
    testing.expect_value(t, CacheCount(cache, scores), 8)
}

@(test)
test_cache_ignores_tables_that_are_not_kept :: proc(t: ^testing.T) {
    test: TestCache
    cache, scores := testCacheMake(&test)
    rows: [][12]u8 = {testRow(1, 1)}
    tables: [1]TableRows = {{table = "other", rows = testList(rows)}}
    CacheApply(cache, SubscribeApplied{rows = {tables = tables[:]}})
    testing.expect_value(t, CacheCount(cache, scores), 0)
    testing.expect_value(t, cache.ignored, 1)
}
