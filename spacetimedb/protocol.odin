package spacetimedb

// The websocket protocol v2 of SpacetimeDB (`v2.bsatn.spacetimedb`, spacetimedb/SpacetimeDB/crates/client-api-messages/src/websocket/v2.rs): the messages a client sends and the ones it
// receives, as BSATN. Encoding writes into a Writer of the caller. Decoding (`ServerMessageDecode`) gives a `ServerMessage` whose strings and byte slices point into the frame that was
// decoded (keep the frame until you are done with the message); the arrays of it (the tables of an update) are made with the `allocator` you pass: an arena that is cleared after every message is
// the way (nothing here keeps a pointer between two messages).
//
// A server frame starts with one byte of compression (0: none): ask for `compression=None` when connecting (connection.odin does) and `ServerFrame` strips the byte.

import "base:runtime"

PROTOCOL_V2 :: "v2.bsatn.spacetimedb"

COMPRESSION_NONE :: u8(0)
COMPRESSION_BROTLI :: u8(1)
COMPRESSION_GZIP :: u8(2)

// ---- what the client sends -----------------------------------------------------------------------------------------------------------------------------------

// Registers a set of queries (`SELECT * FROM table WHERE ...`, one SELECT each) under `query_set_id` (yours, unique in the connection); the answer is a SubscribeApplied with the rows that match
// and then a TransactionUpdate for every change.
EncodeSubscribe :: proc(writer: ^Writer, request_id: u32, query_set_id: u32, queries: []string) {
    WriteTag(writer, 0)
    WriteU32(writer, request_id)
    WriteU32(writer, query_set_id)
    WriteLength(writer, len(queries))
    for query in queries { WriteString(writer, query) }
}

EncodeUnsubscribe :: proc(writer: ^Writer, request_id: u32, query_set_id: u32, send_dropped_rows: bool = false) {
    WriteTag(writer, 1)
    WriteU32(writer, request_id)
    WriteU32(writer, query_set_id)
    WriteU8(writer, 1 if send_dropped_rows else 0)
}

// A query that is run once, no updates follow: the answer is a OneOffQueryResult with the same request_id
EncodeOneOffQuery :: proc(writer: ^Writer, request_id: u32, query: string) {
    WriteTag(writer, 2)
    WriteU32(writer, request_id)
    WriteString(writer, query)
}

// A call of a reducer: `args` is the BSATN of its arguments as a product (the fields one after the other)
EncodeCallReducer :: proc(writer: ^Writer, request_id: u32, reducer: string, args: []u8) {
    WriteTag(writer, 3)
    WriteU32(writer, request_id)
    WriteU8(writer, 0)                      // flags: default
    WriteString(writer, reducer)
    WriteBytes(writer, args)
}

EncodeCallProcedure :: proc(writer: ^Writer, request_id: u32, procedure: string, args: []u8) {
    WriteTag(writer, 4)
    WriteU32(writer, request_id)
    WriteU8(writer, 0)
    WriteString(writer, procedure)
    WriteBytes(writer, args)
}

// Several subscriptions in one step (every one of them is applied at the same moment of the database)
EncodeSubscribeBatch :: proc(writer: ^Writer, request_id: u32, query_set_ids: []u32, queries: [][]string) {
    WriteTag(writer, 5)
    WriteU32(writer, request_id)
    WriteLength(writer, len(query_set_ids))
    for id, i in query_set_ids {
        WriteU32(writer, id)
        WriteLength(writer, len(queries[i]))
        for query in queries[i] { WriteString(writer, query) }
    }
}

// ---- what the client receives ----------------------------------------------------------------------------------------------------------------------------

// A list of rows of one table: BSATN rows one after the other, `data`, and how to cut them: all the same size (`fixed_size`), or the start of each in `offsets`
RowList :: struct {
    fixed_size: u16,
    offsets: []u64,
    data: []u8,
}

RowListCount :: proc(list: RowList) -> int {
    if list.fixed_size > 0 { return len(list.data) / int(list.fixed_size) }
    return len(list.offsets)
}

// The bytes of the row `index` (one row of the table, BSATN of its product), a slice of the frame
RowListRow :: proc(list: RowList, index: int) -> []u8 {
    count: int = RowListCount(list)
    if index < 0 || index >= count { return nil }
    if list.fixed_size > 0 {
        size: int = int(list.fixed_size)
        return list.data[index * size:(index + 1) * size]
    }
    start: int = int(list.offsets[index])
    end: int = int(list.offsets[index + 1]) if index + 1 < len(list.offsets) else len(list.data)
    if start > end || end > len(list.data) { return nil }
    return list.data[start:end]
}

TableRows :: struct {
    table: string,
    rows: RowList,
}

QueryRows :: struct {
    tables: []TableRows,
}

// The changes of one table in a transaction. An event table has only `events` (in `inserts`, with `event` true): rows that are told once and not kept.
TableUpdate :: struct {
    table: string,
    event: bool,
    inserts: RowList,
    deletes: RowList,
}

QuerySetUpdate :: struct {
    query_set_id: u32,
    tables: []TableUpdate,
}

TransactionUpdate :: struct {
    query_sets: []QuerySetUpdate,
}

InitialConnection :: struct {
    identity: Identity,
    connection_id: ConnectionId,
    token: string,
}

SubscribeApplied :: struct {
    request_id: u32,
    query_set_id: u32,
    rows: QueryRows,
}

UnsubscribeApplied :: struct {
    request_id: u32,
    query_set_id: u32,
    has_rows: bool,
    rows: QueryRows,
}

SubscriptionError :: struct {
    request_id: u32,
    has_request_id: bool,
    query_set_id: u32,
    error: string,
}

OneOffQueryResult :: struct {
    request_id: u32,
    ok: bool,
    rows: QueryRows,
    error: string,
}

ReducerOutcomeKind :: enum u8 {
    OK,                 // it ran: `value` is what it returned and `update` the changes it made to what this client subscribed to
    OK_EMPTY,           // it ran and changed nothing that matters here
    ERROR,              // it refused: `value` is the BSATN of its error (usually a string)
    INTERNAL_ERROR,     // the host could not run it: `message`
}

ReducerResult :: struct {
    request_id: u32,
    timestamp: Timestamp,
    outcome: ReducerOutcomeKind,
    value: []u8,
    message: string,
    update: TransactionUpdate,
}

ProcedureResult :: struct {
    request_id: u32,
    timestamp: Timestamp,
    duration: TimeDuration,
    returned: bool,
    value: []u8,
    message: string,
}

SubscribeSetResult :: struct {
    query_set_id: u32,
    ok: bool,
    rows: QueryRows,
    error: string,
}

SubscribeBatchApplied :: struct {
    request_id: u32,
    results: []SubscribeSetResult,
}

ServerMessage :: union {
    InitialConnection,
    SubscribeApplied,
    UnsubscribeApplied,
    SubscriptionError,
    TransactionUpdate,
    OneOffQueryResult,
    ReducerResult,
    ProcedureResult,
    SubscribeBatchApplied,
}

// A frame that came over the socket: the first byte says how it is compressed. `ok` is false for a compressed frame (connect with compression=None) or an empty one.
ServerFrame :: proc(frame: []u8) -> (body: []u8, ok: bool) {
    if len(frame) == 0 || frame[0] != COMPRESSION_NONE { return nil, false }
    return frame[1:], true
}

// Decodes one message (the body of a frame, see ServerFrame). `ok` false: the bytes are not a message of this protocol. The arrays are made with `allocator`.
ServerMessageDecode :: proc(body: []u8, allocator: runtime.Allocator) -> (message: ServerMessage, ok: bool) {
    reader: Reader = ReaderMake(body)
    tag: u8 = ReadTag(&reader)
    switch tag {
    case 0:
        initial: InitialConnection = {identity = ReadIdentity(&reader), connection_id = ReadConnectionId(&reader)}
        initial.token = ReadString(&reader)
        message = initial
    case 1:
        applied: SubscribeApplied = {request_id = ReadU32(&reader), query_set_id = ReadU32(&reader)}
        applied.rows = readQueryRows(&reader, allocator)
        message = applied
    case 2:
        applied: UnsubscribeApplied = {request_id = ReadU32(&reader), query_set_id = ReadU32(&reader)}
        applied.has_rows = ReadTag(&reader) == 0
        if applied.has_rows { applied.rows = readQueryRows(&reader, allocator) }
        message = applied
    case 3:
        error: SubscriptionError
        error.has_request_id = ReadTag(&reader) == 0
        value: u32 = ReadU32(&reader) if error.has_request_id else 0
        error.request_id = value
        error.query_set_id = ReadU32(&reader)
        error.error = ReadString(&reader)
        message = error
    case 4:
        message = readTransactionUpdate(&reader, allocator)
    case 5:
        result: OneOffQueryResult = {request_id = ReadU32(&reader)}
        result.ok = ReadTag(&reader) == 0
        if result.ok { result.rows = readQueryRows(&reader, allocator) } else { result.error = ReadString(&reader) }
        message = result
    case 6:
        result: ReducerResult = {request_id = ReadU32(&reader), timestamp = Timestamp(ReadI64(&reader))}
        switch ReadTag(&reader) {
        case 0:
            result.outcome = .OK
            result.value = ReadBytes(&reader)
            result.update = readTransactionUpdate(&reader, allocator)
        case 1: result.outcome = .OK_EMPTY
        case 2:
            result.outcome = .ERROR
            result.value = ReadBytes(&reader)
        case 3:
            result.outcome = .INTERNAL_ERROR
            result.message = ReadString(&reader)
        case: reader.failed = true
        }
        message = result
    case 7:
        result: ProcedureResult
        switch ReadTag(&reader) {
        case 0:
            result.returned = true
            result.value = ReadBytes(&reader)
        case 1: result.message = ReadString(&reader)
        case: reader.failed = true
        }
        result.timestamp = Timestamp(ReadI64(&reader))
        result.duration = TimeDuration(ReadI64(&reader))
        result.request_id = ReadU32(&reader)
        message = result
    case 8:
        batch: SubscribeBatchApplied = {request_id = ReadU32(&reader)}
        count: int = ReadLength(&reader, 5)
        batch.results = make([]SubscribeSetResult, count, allocator)
        for i in 0 ..< count {
            batch.results[i].query_set_id = ReadU32(&reader)
            batch.results[i].ok = ReadTag(&reader) == 0
            if batch.results[i].ok { batch.results[i].rows = readQueryRows(&reader, allocator) } else { batch.results[i].error = ReadString(&reader) }
        }
        message = batch
    case:
        return nil, false
    }
    return message, !ReaderFailed(&reader)
}

@(private)
readRowList :: proc(reader: ^Reader, allocator: runtime.Allocator) -> RowList {
    list: RowList
    switch ReadTag(reader) {
    case 0:
        list.fixed_size = ReadU16(reader)
    case 1:
        count: int = ReadLength(reader, 8)
        list.offsets = make([]u64, count, allocator)
        for i in 0 ..< count { list.offsets[i] = ReadU64(reader) }
    case:
        reader.failed = true
    }
    list.data = ReadBytes(reader)
    return list
}

@(private)
readQueryRows :: proc(reader: ^Reader, allocator: runtime.Allocator) -> QueryRows {
    count: int = ReadLength(reader, 6)
    rows: QueryRows = {tables = make([]TableRows, count, allocator)}
    for i in 0 ..< count {
        rows.tables[i].table = ReadString(reader)
        rows.tables[i].rows = readRowList(reader, allocator)
    }
    return rows
}

@(private)
readTransactionUpdate :: proc(reader: ^Reader, allocator: runtime.Allocator) -> TransactionUpdate {
    sets: int = ReadLength(reader, 8)
    update: TransactionUpdate = {query_sets = make([]QuerySetUpdate, sets, allocator)}
    for i in 0 ..< sets {
        update.query_sets[i].query_set_id = ReadU32(reader)
        // the server may send several updates of one table: they are kept as they come, in a table update each
        entries: [dynamic]TableUpdate
        entries.allocator = allocator
        tables: int = ReadLength(reader, 8)
        for _ in 0 ..< tables {
            name: string = ReadString(reader)
            rows: int = ReadLength(reader, 1)
            for _ in 0 ..< rows {
                entry: TableUpdate = {table = name}
                switch ReadTag(reader) {
                case 0:
                    entry.inserts = readRowList(reader, allocator)
                    entry.deletes = readRowList(reader, allocator)
                case 1:
                    entry.event = true
                    entry.inserts = readRowList(reader, allocator)
                case:
                    reader.failed = true
                }
                append(&entries, entry)
            }
        }
        update.query_sets[i].tables = entries[:]
    }
    return update
}
