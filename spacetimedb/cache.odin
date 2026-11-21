package spacetimedb

// The client cache: the rows of the subscriptions kept by table, so that a game reads its `players` and does not decode BSATN messages. Feed it every message of `ConnectionPoll` with
// `CacheApply`; it keeps the rows, turns an update (a delete and an insert of the same key in one transaction) into one UPDATE event, and lists what changed in `CacheEvents` for the frame.
//
//     cache: Cache
//     CacheInit(&cache, {slots = slots[:], buckets = buckets[:], bytes = bytes[:], events = events[:], tables = tables[:]})
//     person: int = CacheTableAdd(&cache, "person", key_size = 0)           // key_size: bytes of the primary key at the start of the row, 0: the whole row is the key
//     ...
//     CacheClearEvents(&cache)                                            // once a frame, before the poll loop
//     for message, got := ConnectionPoll(...); got; ... { CacheApply(&cache, message) }
//     for event in CacheEvents(&cache) { ... }                           // event.row / event.old are valid until the next poll (they point into the frame)
//     for row in CacheRows(&cache, person) ...  / CacheCollect(&cache, person, PersonRead, people[:])
//
// Memory: everything is the caller's (slots, hash buckets, the bytes of the rows, events, tables); nothing grows: a full cache sets `Cache.failed` and drops the row. A row of the cache points
// into `bytes`, and is good until the next `CacheApply` (rows may move when the bytes are compacted). A row that two subscriptions both match is counted once per subscription (a reference
// count), so one of them ending does not remove it from the other.

CACHE_NO_SLOT :: i32(-1)

CacheEventKind :: enum u8 {
    INSERT,         // `row` is new
    UPDATE,         // `old` became `row` (same key)
    DELETE,         // `row` is what was removed
}

CacheEvent :: struct {
    kind: CacheEventKind,
    table: int,
    row: []u8,
    old: []u8,
}

CacheTable :: struct {
    name: string,
    key_size: int,
    count: int,
}

CacheSlot :: struct {
    table: u16,
    references: u16,                // how many subscriptions have this row; 0: the slot is free
    pending: bool,                  // being deleted by the update that is applied
    hash: u32,
    offset: u32,                    // of the bytes of the row in `bytes` (after the 8 byte header)
    size: u32,
    next: i32,                      // next in the bucket chain, or in the free list
    event: i32,                     // index of the DELETE event of a pending row
}

CacheStorage :: struct {
    slots: []CacheSlot,
    buckets: []i32,                 // a power of two in length
    bytes: []u8,                    // the rows, each with an 8 byte header (size, slot)
    events: []CacheEvent,
    tables: []CacheTable,
}

Cache :: struct {
    using storage: CacheStorage,
    table_count: int,
    event_count: int,
    free_slot: i32,
    slot_high: int,                 // slots below this index have been used once
    used: int,                      // end of the bytes in use (holes of dead rows included)
    dead: int,                      // bytes of dead rows below `used`
    failed: bool,                   // a row was dropped: a slot, the bytes or a table was missing (the cache is no longer the database)
    events_dropped: bool,           // an event did not fit `events` (the rows are right)
    ignored: int,                   // rows of tables that were not added
}

CACHE_HEADER :: 8
CACHE_DEAD :: u32(0xFFFFFFFF)

CacheInit :: proc(cache: ^Cache, storage: CacheStorage) {
    assert(len(storage.buckets) > 0 && len(storage.buckets) & (len(storage.buckets) - 1) == 0, "buckets: a power of two")
    cache^ = {storage = storage, free_slot = CACHE_NO_SLOT}
    CacheClear(cache)
}

// Forgets every row (a reconnect starts from the answer of the new subscriptions)
CacheClear :: proc(cache: ^Cache) {
    for &bucket in cache.buckets { bucket = CACHE_NO_SLOT }
    for &slot in cache.slots { slot = {} }
    for i in 0 ..< cache.table_count { cache.tables[i].count = 0 }
    cache.free_slot = CACHE_NO_SLOT
    cache.slot_high, cache.used, cache.dead, cache.event_count = 0, 0, 0, 0
    cache.failed, cache.events_dropped, cache.ignored = false, false, 0
}

// Adds a table to keep. Returns its index (-1 when `tables` is full). `key_size` is how many bytes at the start of a row are its primary key (a u64 id: 8); 0 makes the whole row the key,
// then an update arrives as a DELETE and an INSERT.
CacheTableAdd :: proc(cache: ^Cache, name: string, key_size: int = 0) -> int {
    if cache.table_count >= len(cache.tables) { return -1 }
    cache.tables[cache.table_count] = {name = name, key_size = key_size}
    cache.table_count += 1
    return cache.table_count - 1
}

CacheTableFind :: proc(cache: ^Cache, name: string) -> int {
    for i in 0 ..< cache.table_count {
        if cache.tables[i].name == name { return i }
    }
    return -1
}

CacheCount :: proc(cache: ^Cache, table: int) -> int {
    return cache.tables[table].count if table >= 0 && table < cache.table_count else 0
}

CacheClearEvents :: proc(cache: ^Cache) {
    cache.event_count = 0
    cache.events_dropped = false
}

CacheEvents :: proc(cache: ^Cache) -> []CacheEvent {
    return cache.events[:cache.event_count]
}

@(private)
cacheHash :: proc(bytes: []u8) -> u32 {
    hash: u32 = 2166136261
    for b in bytes { hash = (hash ~ u32(b)) * 16777619 }
    return hash
}

@(private)
cacheKey :: proc(cache: ^Cache, table: int, row: []u8) -> []u8 {
    size: int = cache.tables[table].key_size
    return row[:size] if size > 0 && size <= len(row) else row
}

@(private)
cacheRow :: proc(cache: ^Cache, slot: i32) -> []u8 {
    s: ^CacheSlot = &cache.slots[slot]
    return cache.bytes[s.offset:s.offset + s.size]
}

@(private)
cacheFind :: proc(cache: ^Cache, table: int, row: []u8, by_key: bool) -> i32 {
    key: []u8 = cacheKey(cache, table, row)
    hash: u32 = cacheHash(key)
    at: i32 = cache.buckets[int(hash) & (len(cache.buckets) - 1)]
    for at != CACHE_NO_SLOT {
        s: ^CacheSlot = &cache.slots[at]
        if int(s.table) == table && s.hash == hash {
            stored: []u8 = cacheRow(cache, at)
            if by_key {
                if string(cacheKey(cache, table, stored)) == string(key) { return at }
            } else if string(stored) == string(row) {
                return at
            }
        }
        at = s.next
    }
    return CACHE_NO_SLOT
}

@(private)
cacheCompact :: proc(cache: ^Cache) {
    at: int
    to: int
    for at < cache.used {
        size: int = int(readU32(cache.bytes[at:]))
        slot: u32 = readU32(cache.bytes[at + 4:])
        total: int = CACHE_HEADER + size
        if slot != CACHE_DEAD {
            if to != at { copy(cache.bytes[to:to + total], cache.bytes[at:at + total]) }
            cache.slots[slot].offset = u32(to + CACHE_HEADER)
            to += total
        }
        at += total
    }
    cache.used, cache.dead = to, 0
}

@(private)
readU32 :: proc(bytes: []u8) -> u32 {
    return u32(bytes[0]) | u32(bytes[1]) << 8 | u32(bytes[2]) << 16 | u32(bytes[3]) << 24
}

@(private)
writeU32 :: proc(bytes: []u8, value: u32) {
    bytes[0], bytes[1], bytes[2], bytes[3] = u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)
}

@(private)
cacheInsert :: proc(cache: ^Cache, table: int, row: []u8) -> i32 {
    total: int = CACHE_HEADER + len(row)
    if cache.used + total > len(cache.bytes) && cache.dead > 0 { cacheCompact(cache) }
    slot: i32 = cache.free_slot
    if slot != CACHE_NO_SLOT {
        cache.free_slot = cache.slots[slot].next
    } else if cache.slot_high < len(cache.slots) {
        slot = i32(cache.slot_high)
        cache.slot_high += 1
    }
    if slot == CACHE_NO_SLOT || cache.used + total > len(cache.bytes) {
        if slot != CACHE_NO_SLOT {
            cache.slots[slot].next = cache.free_slot            // give the slot back
            cache.free_slot = slot
        }
        cache.failed = true
        return CACHE_NO_SLOT
    }
    writeU32(cache.bytes[cache.used:], u32(len(row)))
    writeU32(cache.bytes[cache.used + 4:], u32(slot))
    copy(cache.bytes[cache.used + CACHE_HEADER:], row)
    hash: u32 = cacheHash(cacheKey(cache, table, row))
    bucket: int = int(hash) & (len(cache.buckets) - 1)
    cache.slots[slot] = {table = u16(table), references = 1, hash = hash, offset = u32(cache.used + CACHE_HEADER), size = u32(len(row)), next = cache.buckets[bucket], event = CACHE_NO_SLOT}
    cache.buckets[bucket] = slot
    cache.used += total
    cache.tables[table].count += 1
    return slot
}

@(private)
cacheRemove :: proc(cache: ^Cache, slot: i32) {
    s: ^CacheSlot = &cache.slots[slot]
    bucket: int = int(s.hash) & (len(cache.buckets) - 1)
    if cache.buckets[bucket] == slot {
        cache.buckets[bucket] = s.next
    } else {
        at: i32 = cache.buckets[bucket]
        for at != CACHE_NO_SLOT && cache.slots[at].next != slot { at = cache.slots[at].next }
        if at != CACHE_NO_SLOT { cache.slots[at].next = s.next }
    }
    writeU32(cache.bytes[int(s.offset) - 4:], CACHE_DEAD)        // the slot field of the header
    cache.dead += CACHE_HEADER + int(s.size)
    cache.tables[s.table].count -= 1
    s^ = {next = cache.free_slot}
    cache.free_slot = slot
}

@(private)
cacheEvent :: proc(cache: ^Cache, event: CacheEvent) -> i32 {
    if cache.event_count >= len(cache.events) {
        cache.events_dropped = true
        return CACHE_NO_SLOT
    }
    cache.events[cache.event_count] = event
    cache.event_count += 1
    return i32(cache.event_count - 1)
}

@(private)
cacheAddRow :: proc(cache: ^Cache, table: int, row: []u8) {
    existing: i32 = cacheFind(cache, table, row, false)
    if existing != CACHE_NO_SLOT {
        cache.slots[existing].references += 1
        return
    }
    if cacheInsert(cache, table, row) != CACHE_NO_SLOT { cacheEvent(cache, {kind = .INSERT, table = table, row = row}) }
}

// Applies the changes of one table: deletes first (marked), then the inserts, so that a delete and an insert of one key become an UPDATE, then the deletes that stay are removed.
@(private)
cacheApplyTable :: proc(cache: ^Cache, table: int, deletes: RowList, inserts: RowList) {
    delete_count: int = RowListCount(deletes)
    for i in 0 ..< delete_count {
        row: []u8 = RowListRow(deletes, i)
        slot: i32 = cacheFind(cache, table, row, false)
        if slot == CACHE_NO_SLOT { continue }
        s: ^CacheSlot = &cache.slots[slot]
        if s.references > 1 {
            s.references -= 1
        } else {
            s.pending = true
            s.event = cacheEvent(cache, {kind = .DELETE, table = table, row = row})
        }
    }
    keyed: bool = cache.tables[table].key_size > 0
    for i in 0 ..< RowListCount(inserts) {
        row: []u8 = RowListRow(inserts, i)
        if keyed {
            slot: i32 = cacheFind(cache, table, row, true)
            if slot != CACHE_NO_SLOT && cache.slots[slot].pending {
                event: i32 = cache.slots[slot].event
                if event != CACHE_NO_SLOT {
                    cache.events[event].kind = .UPDATE
                    cache.events[event].old = cache.events[event].row
                    cache.events[event].row = row
                }
                cacheRemove(cache, slot)
                if cacheInsert(cache, table, row) == CACHE_NO_SLOT && event != CACHE_NO_SLOT { cache.events[event].kind = .DELETE; cache.events[event].row = cache.events[event].old }
                continue
            }
        }
        cacheAddRow(cache, table, row)
    }
    for i in 0 ..< delete_count {
        slot: i32 = cacheFind(cache, table, RowListRow(deletes, i), false)
        if slot != CACHE_NO_SLOT && cache.slots[slot].pending { cacheRemove(cache, slot) }
    }
}

@(private)
cacheApplyRows :: proc(cache: ^Cache, rows: QueryRows, remove: bool) {
    for entry in rows.tables {
        table: int = CacheTableFind(cache, entry.table)
        if table < 0 {
            cache.ignored += RowListCount(entry.rows)
            continue
        }
        if remove { cacheApplyTable(cache, table, entry.rows, {}) } else { cacheApplyTable(cache, table, {}, entry.rows) }
    }
}

@(private)
cacheApplyUpdate :: proc(cache: ^Cache, update: TransactionUpdate) {
    for set in update.query_sets {
        for entry in set.tables {
            table: int = CacheTableFind(cache, entry.table)
            if table < 0 {
                cache.ignored += RowListCount(entry.inserts) + RowListCount(entry.deletes)
                continue
            }
            if entry.event {
                for i in 0 ..< RowListCount(entry.inserts) { cacheEvent(cache, {kind = .INSERT, table = table, row = RowListRow(entry.inserts, i)}) }
            } else {
                cacheApplyTable(cache, table, entry.deletes, entry.inserts)
            }
        }
    }
}

// Applies a message of the server to the cache: the rows of an applied subscription, the changes of a transaction (also the ones inside a reducer result), the rows dropped by an unsubscribe.
// Other messages are ignored. Returns true when the message could have changed the cache.
CacheApply :: proc(cache: ^Cache, message: ServerMessage) -> bool {
    switch value in message {
    case SubscribeApplied:
        cacheApplyRows(cache, value.rows, false)
    case UnsubscribeApplied:
        if value.has_rows { cacheApplyRows(cache, value.rows, true) }
    case SubscribeBatchApplied:
        for result in value.results {
            if result.ok { cacheApplyRows(cache, result.rows, false) }
        }
    case TransactionUpdate:
        cacheApplyUpdate(cache, value)
    case ReducerResult:
        if value.outcome != .OK { return false }
        cacheApplyUpdate(cache, value.update)
    case InitialConnection, SubscriptionError, OneOffQueryResult, ProcedureResult:
        return false
    }
    return true
}

// ---- reading -----------------------------------------------------------------------------------------------------------------------------------------------------

// The row of a table with this key (the first `key_size` bytes of the row, or the whole row when the table has no key size). A slice of the cache.
CacheFind :: proc(cache: ^Cache, table: int, key: []u8) -> (row: []u8, found: bool) {
    if table < 0 || table >= cache.table_count { return nil, false }
    hash: u32 = cacheHash(key)
    at: i32 = cache.buckets[int(hash) & (len(cache.buckets) - 1)]
    for at != CACHE_NO_SLOT {
        s: ^CacheSlot = &cache.slots[at]
        if int(s.table) == table && s.hash == hash {
            stored: []u8 = cacheRow(cache, at)
            if string(cacheKey(cache, table, stored)) == string(key) { return stored, true }
        }
        at = s.next
    }
    return nil, false
}

CacheIterator :: struct {
    table: int,
    slot: int,
}

// The next row of a table (order of insertion until rows are removed and reused):
//     it: CacheIterator = {table = person}
//     for row in CacheNext(&cache, &it) { ... }
CacheNext :: proc(cache: ^Cache, it: ^CacheIterator) -> (row: []u8, ok: bool) {
    for it.slot < cache.slot_high {
        slot: i32 = i32(it.slot)
        it.slot += 1
        s: ^CacheSlot = &cache.slots[slot]
        if s.references > 0 && int(s.table) == it.table { return cacheRow(cache, slot), true }
    }
    return nil, false
}

// Reads every row of a table into `out` with a reader of the row type (generated: `PersonRead :: proc(reader: ^Reader) -> Person`). Returns the filled part of `out`; strings and bytes of the
// rows point into the cache. `out` too small: the rest is left out (compare with `CacheCount`).
CacheCollect :: proc(cache: ^Cache, table: int, read: proc(reader: ^Reader) -> $T, out: []T) -> []T {
    count: int
    it: CacheIterator = {table = table}
    for row in CacheNext(cache, &it) {
        if count >= len(out) { break }
        reader: Reader = ReaderMake(row)
        out[count] = read(&reader)
        count += 1
    }
    return out[:count]
}
