package spacetimedb_module

// A SpacetimeDB module written in Odin. A module is a WebAssembly program that the database runs: it describes its tables and reducers when it is asked (`__describe_module__`), and the database
// calls a reducer by its number (`__call_reducer__`) inside of a transaction. The module reads and writes tables through the host functions of abi.odin, and its rows are BSATN.
//
//     package main
//
//     import module "path/to/spacetimedb/module"
//     import "path/to/spacetimedb/bsatn"
//
//     people: module.Table
//
//     @(export)
//     __preinit__10_define :: proc "c" () { module.Define(define) }           // the database asks for the description after this
//
//     define :: proc(m: ^module.Module) {
//         people = module.TableAdd(m, "person", {{"name", .STRING}}, public = true)
//         module.ReducerAdd(m, "add", {{"name", .STRING}}, add)
//     }
//
//     add :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
//         name: string = bsatn.ReadString(args)
//         row: [64]u8
//         writer: bsatn.Writer = bsatn.WriterMake(row[:])
//         bsatn.WriteString(&writer, name)
//         return module.TableInsert(people, bsatn.WriterBytes(&writer))      // "" or the text of an error
//     }
//
// Build it with `odin run spacetimedb/tool/build_module -- path/to/package` (that is `odin build <package> -target:freestanding_wasm32 -no-entry-point` and an output file), publish the .wasm with
// `DatabasePublish` or the CLI. There is no heap in the module: every buffer is a fixed array of this package or of the module (`CAPACITY` below); a reducer that needs memory gets the arena of its
// call in `ctx.allocator` (cleared after the reducer).
//
// Column types: the primitive ones, `.IDENTITY`, `.CONNECTION_ID`, `.TIMESTAMP`, `.TIME_DURATION`, `.SCHEDULE_AT`, and `.ARRAY` / `.OPTION` of one of those (the `element` of the column).
// A table can have a primary key, unique columns, an automatic increment column, btree indexes and a scheduled reducer (`TableOptions`); rows are read and deleted by an index (`TableFind`,
// `TableDeleteBy`, `TableUpdate`) and deleted by value (`TableDelete`).
//
// Limits: a reducer has no return value; views and procedures are not described yet (they need the V10 description, TODO.md); structs and enums are not column types (flatten them into
// columns); only the V9 description of the module is written.

import "base:runtime"
import "core:mem"
import "../bsatn"

MAX_TABLES :: 16
MAX_COLUMNS :: 16
MAX_REDUCERS :: 32
MAX_INDEXES :: 8
MAX_INDEX_COLUMNS :: 4

ARGUMENT_BUFFER :: 1 << 16          // the biggest argument list of a reducer
DESCRIPTION_BUFFER :: 1 << 15       // the biggest description of the module
ROW_BUFFER :: 1 << 16               // the biggest row, and the buffer a scan reads its rows through
CALL_ARENA :: 1 << 16               // the memory of one reducer call

// The type of a column: the number is the tag of the type in the description (spacetimedb/SpacetimeDB/crates/sats/src/algebraic_type.rs)
ColumnType :: enum u8 {
    ARRAY = 3,          // of `Column.element`
    STRING = 4,
    BOOL = 5,
    I8 = 6,
    U8 = 7,
    I16 = 8,
    U16 = 9,
    I32 = 10,
    U32 = 11,
    I64 = 12,
    U64 = 13,
    I128 = 14,
    U128 = 15,
    I256 = 16,
    U256 = 17,
    F32 = 18,
    F64 = 19,
    // the types the database defines for itself: not tags of the description but products and sums that it knows by their field names
    OPTION = 100,       // of `Column.element`
    IDENTITY = 101,
    CONNECTION_ID = 102,
    TIMESTAMP = 103,
    TIME_DURATION = 104,
    SCHEDULE_AT = 105,  // Interval(TimeDuration) or Time(Timestamp): when a scheduled reducer runs
}

Column :: struct {
    name: string,
    type: ColumnType,
    element: ColumnType,        // for `.ARRAY` and `.OPTION`: the type of the items (not an array or an option itself)
}

ReducerKind :: enum u8 {
    NORMAL,             // called by a client by its name
    INIT,               // runs once when the database is made
    ON_CONNECT,         // runs when a client connects
    ON_DISCONNECT,      // and when it goes away
}

// What a reducer knows about its call: who called it, from which connection (zero for a call that no client made), when, and an arena for the call
ReducerContext :: struct {
    sender: bsatn.Identity,
    connection: bsatn.ConnectionId,
    timestamp: bsatn.Timestamp,
    allocator: runtime.Allocator,
}

// The reducer reads its arguments from `args` (the fields of its parameters in order) and returns "" or the text of an error: the transaction is rolled back and the caller gets the text
ReducerProc :: #type proc(ctx: ^ReducerContext, args: ^bsatn.Reader) -> string

Table :: struct {
    index: int,                     // the place of the table in the module (made by TableAdd)
}

// A btree index over columns (by their place in the table): a read by `TableFind` needs one
Index :: struct {
    columns: []int,
}

// What a table has besides its columns
TableOptions :: struct {
    unique: []int,                  // columns whose values are unique (a second insert of one is refused)
    auto_increment: int,            // a column (an integer) that the database numbers when the row is inserted with 0 (used when `has_auto_increment`)
    has_auto_increment: bool,
    indexes: []Index,
    schedule_reducer: string,       // a scheduled table: the reducer that runs for each row when its time (`schedule_column`, a `.SCHEDULE_AT`) comes; the row is its argument
    schedule_column: int,
}

IndexDef :: struct {
    columns: [MAX_INDEX_COLUMNS]u16,
    count: int,
    id: IndexId,
    id_known: bool,
}

TableDef :: struct {
    name: string,
    public: bool,
    columns: [MAX_COLUMNS]Column,
    column_count: int,
    primary_key: int,               // the column, -1 for none
    id: TableId,                    // found by name at the first use
    id_known: bool,
    unique: [MAX_COLUMNS]u16,
    unique_count: int,
    auto_column: int,               // -1 for none
    indexes: [MAX_INDEXES]IndexDef, // the ones given, the primary key and the unique columns (each is a btree index of the database)
    index_count: int,
    schedule_reducer: string,
    schedule_column: int,
}

ReducerDef :: struct {
    name: string,
    columns: [MAX_COLUMNS]Column,   // its parameters
    column_count: int,
    kind: ReducerKind,
    call: ReducerProc,
    scheduled_table: int,           // >= 0: the reducer of a scheduled table, its one argument is a row of that table
}

Module :: struct {
    tables: [MAX_TABLES]TableDef,
    table_count: int,
    reducers: [MAX_REDUCERS]ReducerDef,
    reducer_count: int,
    failed: bool,                   // more tables, reducers or columns were added than there is room for
}

@(private)
module: Module
@(private)
defined: bool
@(private)
define_proc: proc(module: ^Module)
@(private)
argument_buffer: [ARGUMENT_BUFFER]u8
@(private)
description_buffer: [DESCRIPTION_BUFFER]u8
@(private)
row_buffer: [ROW_BUFFER]u8
@(private)
call_memory: [CALL_ARENA]u8
@(private)
call_arena: mem.Arena
@(private)
call_arena_ready: bool

// Tells the library where the tables and the reducers are described: `define` is called when the database asks for the description and again before a call (an instance of the module is made for
// each), so it only adds tables and reducers (TableAdd, ReducerAdd). Call it from an export called `__preinit__...`, which the host runs before anything else.
Define :: proc "c" (define: proc(module: ^Module)) {
    define_proc = define
}

@(private)
ensureDefined :: proc() {
    if defined { return }
    defined = true
    module = {}
    if define_proc != nil { define_proc(&module) }
}

// Adds a table. `columns` are its fields in the order of the rows. `public` tables can be subscribed to by clients; a private table is for the module only.
TableAdd :: proc(m: ^Module, name: string, columns: []Column, public: bool = false, primary_key: int = -1, options: TableOptions = {}) -> Table {
    if m.table_count >= MAX_TABLES || len(columns) > MAX_COLUMNS {
        m.failed = true
        return {index = -1}
    }
    table: ^TableDef = &m.tables[m.table_count]
    table^ = {name = name, public = public, column_count = len(columns), primary_key = primary_key, auto_column = options.auto_increment if options.has_auto_increment else -1}
    table.schedule_reducer, table.schedule_column = options.schedule_reducer, options.schedule_column
    for column, i in columns { table.columns[i] = column }
    if len(options.unique) > MAX_COLUMNS { m.failed = true }
    for column in options.unique {
        if table.unique_count < MAX_COLUMNS {
            table.unique[table.unique_count] = u16(column)
            table.unique_count += 1
        }
    }
    // the database keeps a btree index for a primary key and for every unique column: they are the ones `TableFind` can use
    if primary_key >= 0 { indexAdd(m, table, {primary_key}) }
    for column in options.unique { indexAdd(m, table, {column}) }
    for index in options.indexes { indexAdd(m, table, index.columns) }
    m.table_count += 1
    return {index = m.table_count - 1}
}

@(private)
indexAdd :: proc(m: ^Module, table: ^TableDef, columns: []int) {
    if len(columns) == 0 || len(columns) > MAX_INDEX_COLUMNS || table.index_count >= MAX_INDEXES {
        m.failed = true
        return
    }
    for i in 0 ..< table.index_count {
        existing: ^IndexDef = &table.indexes[i]
        if existing.count == len(columns) {
            same: bool = true
            for column, j in columns { if int(existing.columns[j]) != column { same = false } }
            if same { return }
        }
    }
    definition: ^IndexDef = &table.indexes[table.index_count]
    definition^ = {count = len(columns)}
    for column, i in columns { definition.columns[i] = u16(column) }
    table.index_count += 1
}

// Adds a reducer: `parameters` are the fields of its arguments in order (what a client sends is checked against them by the host, the reducer reads them from the Reader)
ReducerAdd :: proc(m: ^Module, name: string, parameters: []Column, call: ReducerProc, kind: ReducerKind = .NORMAL) {
    if m.reducer_count >= MAX_REDUCERS || len(parameters) > MAX_COLUMNS {
        m.failed = true
        return
    }
    reducer: ^ReducerDef = &m.reducers[m.reducer_count]
    reducer^ = {name = name, column_count = len(parameters), kind = kind, call = call, scheduled_table = -1}
    for column, i in parameters { reducer.columns[i] = column }
    m.reducer_count += 1
}

// Adds the reducer that a scheduled table runs for each of its rows (`TableOptions.schedule_reducer`): the one argument is a whole row of the table, which the reducer reads field by field.
ReducerAddScheduled :: proc(m: ^Module, name: string, table: Table, call: ReducerProc) {
    if m.reducer_count >= MAX_REDUCERS {
        m.failed = true
        return
    }
    m.reducers[m.reducer_count] = {name = name, call = call, scheduled_table = table.index}
    m.reducer_count += 1
}

// ---- the description ------------------------------------------------------------------------------------------------------------------------------------------------

// A product with one named field of a primitive type: how the database writes its own Identity, Timestamp and the like
@(private)
writeWrapper :: proc(writer: ^bsatn.Writer, field: string, tag: ColumnType) {
    bsatn.WriteTag(writer, 2)
    bsatn.WriteLength(writer, 1)
    bsatn.WriteTag(writer, 0)
    bsatn.WriteString(writer, field)
    bsatn.WriteTag(writer, u8(tag))
}

@(private)
writeType :: proc(writer: ^bsatn.Writer, type: ColumnType, element: ColumnType) {
    switch type {
    case .ARRAY:
        bsatn.WriteTag(writer, 3)
        writeType(writer, element, .STRING)
    case .OPTION:
        bsatn.WriteTag(writer, 1)               // a sum of some(T) and none
        bsatn.WriteLength(writer, 2)
        bsatn.WriteTag(writer, 0)
        bsatn.WriteString(writer, "some")
        writeType(writer, element, .STRING)
        bsatn.WriteTag(writer, 0)
        bsatn.WriteString(writer, "none")
        bsatn.WriteTag(writer, 2)               // an empty product
        bsatn.WriteLength(writer, 0)
    case .IDENTITY: writeWrapper(writer, "__identity__", .U256)
    case .CONNECTION_ID: writeWrapper(writer, "__connection_id__", .U128)
    case .TIMESTAMP: writeWrapper(writer, "__timestamp_micros_since_unix_epoch__", .I64)
    case .TIME_DURATION: writeWrapper(writer, "__time_duration_micros__", .I64)
    case .SCHEDULE_AT:
        bsatn.WriteTag(writer, 1)
        bsatn.WriteLength(writer, 2)
        bsatn.WriteTag(writer, 0)
        bsatn.WriteString(writer, "Interval")
        writeWrapper(writer, "__time_duration_micros__", .I64)
        bsatn.WriteTag(writer, 0)
        bsatn.WriteString(writer, "Time")
        writeWrapper(writer, "__timestamp_micros_since_unix_epoch__", .I64)
    case .STRING, .BOOL, .I8, .U8, .I16, .U16, .I32, .U32, .I64, .U64, .I128, .U128, .I256, .U256, .F32, .F64:
        bsatn.WriteTag(writer, u8(type))
    }
}

@(private)
writeColumns :: proc(writer: ^bsatn.Writer, columns: []Column) {
    bsatn.WriteLength(writer, len(columns))
    for column in columns {
        bsatn.WriteTag(writer, 0)               // the name is Some
        bsatn.WriteString(writer, column.name)
        writeType(writer, column.type, column.element)
    }
}

// The name the database gives a btree index: table, columns, `idx_btree`
@(private)
indexName :: proc(table: ^TableDef, index: ^IndexDef, buffer: []u8) -> string {
    at: int
    put :: proc(buffer: []u8, at: ^int, text: string) {
        count: int = min(len(text), len(buffer) - at^)
        copy(buffer[at^:at^ + count], text[:count])
        at^ += count
    }
    put(buffer, &at, table.name)
    for i in 0 ..< index.count {
        put(buffer, &at, "_")
        put(buffer, &at, table.columns[index.columns[i]].name)
    }
    put(buffer, &at, "_idx_btree")
    return string(buffer[:at])
}

@(private)
writeColList :: proc(writer: ^bsatn.Writer, columns: []u16) {
    bsatn.WriteLength(writer, len(columns))
    for column in columns { bsatn.WriteU16(writer, column) }
}

// RawModuleDef::V9: the typespace (one product type for each table), the tables, the reducers, the names of the table types, and the lists that are empty
@(private)
describe :: proc(writer: ^bsatn.Writer) {
    bsatn.WriteTag(writer, 1)                   // V9
    bsatn.WriteLength(writer, module.table_count)
    for i in 0 ..< module.table_count {
        table: ^TableDef = &module.tables[i]
        bsatn.WriteTag(writer, 2)               // a product type
        writeColumns(writer, table.columns[:table.column_count])
    }
    bsatn.WriteLength(writer, module.table_count)
    for i in 0 ..< module.table_count {
        table: ^TableDef = &module.tables[i]
        bsatn.WriteString(writer, table.name)
        bsatn.WriteU32(writer, u32(i))          // product_type_ref
        if table.primary_key >= 0 {
            bsatn.WriteLength(writer, 1)
            bsatn.WriteU16(writer, u16(table.primary_key))
        } else {
            bsatn.WriteLength(writer, 0)
        }
        bsatn.WriteLength(writer, table.index_count)
        for index_number in 0 ..< table.index_count {
            index: ^IndexDef = &table.indexes[index_number]
            name_buffer: [128]u8
            bsatn.WriteTag(writer, 0)           // name: Some (the one the database would make)
            bsatn.WriteString(writer, indexName(table, index, name_buffer[:]))
            bsatn.WriteTag(writer, 1)           // accessor_name: None
            bsatn.WriteTag(writer, 0)           // BTree
            writeColList(writer, index.columns[:index.count])
        }
        unique_total: int = table.unique_count + (1 if table.primary_key >= 0 else 0)
        bsatn.WriteLength(writer, unique_total)
        if table.primary_key >= 0 {
            bsatn.WriteTag(writer, 1)           // name: None
            bsatn.WriteTag(writer, 0)           // Unique
            key: [1]u16 = {u16(table.primary_key)}
            writeColList(writer, key[:])
        }
        for u in 0 ..< table.unique_count {
            bsatn.WriteTag(writer, 1)
            bsatn.WriteTag(writer, 0)
            writeColList(writer, table.unique[u:u + 1])
        }
        if table.auto_column >= 0 {
            bsatn.WriteLength(writer, 1)
            bsatn.WriteTag(writer, 1)           // name: None
            bsatn.WriteU16(writer, u16(table.auto_column))
            bsatn.WriteTag(writer, 1)           // start, min, max: None
            bsatn.WriteTag(writer, 1)
            bsatn.WriteTag(writer, 1)
            bsatn.WriteU64(writer, 1)           // increment: 1 as an i128
            bsatn.WriteU64(writer, 0)
        } else {
            bsatn.WriteLength(writer, 0)
        }
        if table.schedule_reducer != "" {
            bsatn.WriteTag(writer, 0)           // schedule: Some
            bsatn.WriteTag(writer, 1)           // name: None
            bsatn.WriteString(writer, table.schedule_reducer)
            bsatn.WriteU16(writer, u16(table.schedule_column))
        } else {
            bsatn.WriteTag(writer, 1)           // schedule: None
        }
        bsatn.WriteU8(writer, 1)                // table_type: User
        bsatn.WriteU8(writer, 0 if table.public else 1)     // table_access: Public, Private
    }
    bsatn.WriteLength(writer, module.reducer_count)
    for i in 0 ..< module.reducer_count {
        reducer: ^ReducerDef = &module.reducers[i]
        bsatn.WriteString(writer, reducer.name)
        if reducer.scheduled_table >= 0 {
            bsatn.WriteLength(writer, 1)        // one argument, `arg`: a reference to the product type of the table
            bsatn.WriteTag(writer, 0)
            bsatn.WriteString(writer, "arg")
            bsatn.WriteTag(writer, 0)
            bsatn.WriteU32(writer, u32(reducer.scheduled_table))
        } else {
            writeColumns(writer, reducer.columns[:reducer.column_count])
        }
        switch reducer.kind {
        case .NORMAL:
            bsatn.WriteTag(writer, 1)           // lifecycle: None
        case .INIT:
            bsatn.WriteTag(writer, 0)
            bsatn.WriteU8(writer, 0)
        case .ON_CONNECT:
            bsatn.WriteTag(writer, 0)
            bsatn.WriteU8(writer, 1)
        case .ON_DISCONNECT:
            bsatn.WriteTag(writer, 0)
            bsatn.WriteU8(writer, 2)
        }
    }
    bsatn.WriteLength(writer, module.table_count)       // the names of the types of the rows: the table name with a capital
    for i in 0 ..< module.table_count {
        table: ^TableDef = &module.tables[i]
        bsatn.WriteLength(writer, 0)            // scope
        capitalised: [64]u8
        count: int = min(len(table.name), len(capitalised))
        copy(capitalised[:count], table.name[:count])
        if count > 0 && capitalised[0] >= 'a' && capitalised[0] <= 'z' { capitalised[0] -= 32 }
        bsatn.WriteString(writer, string(capitalised[:count]))
        bsatn.WriteU32(writer, u32(i))          // ty
        bsatn.WriteBool(writer, true)           // custom_ordering
    }
    bsatn.WriteLength(writer, 0)                // misc_exports
    bsatn.WriteLength(writer, 0)                // row_level_security
}

@(private)
sinkWrite :: proc(sink: BytesSink, bytes: []u8) -> bool {
    written: int
    for written < len(bytes) {
        count: uint = uint(len(bytes)) - uint(written)
        if host_bytes_sink_write(sink, raw_data(bytes[written:]), &count) != 0 { return false }
        if count == 0 { return false }
        written += int(count)
    }
    return true
}

// The host asks the module what it is: the description, BSATN, into the sink
@(export)
__describe_module__ :: proc "c" (sink: BytesSink) {
    context = moduleContext()
    ensureDefined()
    writer: bsatn.Writer = bsatn.WriterMake(description_buffer[:])
    describe(&writer)
    if !bsatn.WriterFailed(&writer) && !module.failed { sinkWrite(sink, bsatn.WriterBytes(&writer)) }
}

@(private)
moduleContext :: proc "contextless" () -> runtime.Context {
    context = runtime.default_context()
    if !call_arena_ready {
        mem.arena_init(&call_arena, call_memory[:])
        call_arena_ready = true
    }
    context.allocator = mem.arena_allocator(&call_arena)
    return context
}

// ---- the call of a reducer ---------------------------------------------------------------------------------------------------------------------------------------

@(private)
readArguments :: proc(source: BytesSource) -> (bytes: []u8, ok: bool) {
    if source == 0 { return argument_buffer[:0], true }       // no arguments: the invalid source
    length: int
    for {
        count: uint = uint(len(argument_buffer) - length)
        if count == 0 { return nil, false }
        result: i16 = host_bytes_source_read(source, raw_data(argument_buffer[length:]), &count)
        length += int(count)
        if result == -1 { break }                // the source is exhausted
        if result != 0 { return nil, false }
    }
    return argument_buffer[:length], true
}

// The host calls a reducer by the number it has in the description. The return value is 0 when it ran, 1 when it failed (the error sink then holds the text)
@(export)
__call_reducer__ :: proc "c" (id: u32, sender_0: u64, sender_1: u64, sender_2: u64, sender_3: u64, connection_0: u64, connection_1: u64, timestamp: u64, args: BytesSource, error: BytesSink) -> i32 {
    context = moduleContext()
    ensureDefined()
    if int(id) >= module.reducer_count { return 1 }
    ctx: ReducerContext = {timestamp = bsatn.Timestamp(timestamp), allocator = context.allocator}
    senders: [4]u64 = {sender_0, sender_1, sender_2, sender_3}
    connections: [2]u64 = {connection_0, connection_1}
    for i in 0 ..< 4 {
        for byte in 0 ..< 8 { ctx.sender[i * 8 + byte] = u8(senders[i] >> u32(byte * 8)) }
    }
    for i in 0 ..< 2 {
        for byte in 0 ..< 8 { ctx.connection[i * 8 + byte] = u8(connections[i] >> u32(byte * 8)) }
    }
    bytes, ok := readArguments(args)
    if !ok {
        sinkWrite(error, transmute([]u8)string("the arguments are too big or could not be read"))
        return 1
    }
    reader: bsatn.Reader = bsatn.ReaderMake(bytes)
    message: string = module.reducers[id].call(&ctx, &reader)
    free_all(context.allocator)
    if message != "" {
        sinkWrite(error, transmute([]u8)message)
        return 1
    }
    return 0
}

// ---- tables ----------------------------------------------------------------------------------------------------------------------------------------------------------------

@(private)
tableId :: proc(table: Table) -> (id: TableId, ok: bool) {
    if table.index < 0 || table.index >= module.table_count { return 0, false }
    definition: ^TableDef = &module.tables[table.index]
    if !definition.id_known {
        name: string = definition.name
        if host_table_id_from_name(raw_data(transmute([]u8)name), uint(len(name)), &definition.id) != 0 { return 0, false }
        definition.id_known = true
    }
    return definition.id, true
}

// Inserts a row (its BSATN: the fields of the table in order). "" or the text of the error (a unique key that exists, a row that does not fit the table)
TableInsert :: proc(table: Table, row: []u8) -> string {
    _, message := TableInsertRow(table, row)
    return message
}

// The same, and the row as it was stored: the automatic increment column holds the number the database gave. The slice is the row buffer of the module, good until the next table call.
TableInsertRow :: proc(table: Table, row: []u8) -> (stored: []u8, message: string) {
    id, found := tableId(table)
    if !found { return nil, "no such table" }
    if len(row) > len(row_buffer) { return nil, "the row is too big" }
    copy(row_buffer[:], row)
    length: uint = uint(len(row))
    #partial switch Errno(host_insert(id, raw_data(row_buffer[:]), &length)) {
    case .OK: return row_buffer[:length], ""
    case .UNIQUE_ALREADY_EXISTS: return nil, "a row with the same unique value exists"
    case .BSATN_DECODE_ERROR: return nil, "the row does not match the table"
    case .NO_SUCH_TABLE: return nil, "no such table"
    case .SCHEDULE_AT_DELAY_TOO_LONG: return nil, "the schedule is too far away"
    case: return nil, "the insert failed"
    }
}

// How many rows the table has
TableCount :: proc(table: Table) -> u64 {
    id, found := tableId(table)
    if !found { return 0 }
    count: u64
    host_table_row_count(id, &count)
    return count
}

// Deletes every row of the table; returns how many there were
TableClear :: proc(table: Table) -> u64 {
    id, found := tableId(table)
    if !found { return 0 }
    count: u64
    host_clear(id, &count)
    return count
}

// Reads every row of the table: `each` is called with a Reader at the start of a row and has to read exactly that row (the fields in order) and return true to go on. The rows arrive in batches
// through the module's row buffer; a row that is bigger than the buffer stops the scan (false).
TableScan :: proc(table: Table, user: rawptr, each: proc(user: rawptr, row: ^bsatn.Reader) -> bool) -> bool {
    id, found := tableId(table)
    if !found { return false }
    iterator: RowIter
    if host_table_scan(id, &iterator) != 0 { return false }
    return readRows(iterator, user, each)
}

@(private)
readRows :: proc(iterator: RowIter, user: rawptr, each: proc(user: rawptr, row: ^bsatn.Reader) -> bool) -> bool {
    for {
        length: uint = uint(len(row_buffer))
        result: i16 = host_row_iter_advance(iterator, raw_data(row_buffer[:]), &length)
        if result > 0 {
            host_row_iter_close(iterator)
            return false                         // a row that does not fit, or an error
        }
        reader: bsatn.Reader = bsatn.ReaderMake(row_buffer[:length])
        for bsatn.ReaderLeft(&reader) > 0 {
            if !each(user, &reader) || bsatn.ReaderFailed(&reader) {
                if result != -1 { host_row_iter_close(iterator) }
                return !bsatn.ReaderFailed(&reader)
            }
        }
        if result == -1 { return true }           // the iterator is exhausted and gone
    }
}

// ---- by an index ------------------------------------------------------------------------------------------------------------------------------------------------

@(private)
indexId :: proc(table: Table, columns: []int) -> (id: IndexId, ok: bool) {
    if table.index < 0 || table.index >= module.table_count || len(columns) == 0 || len(columns) > MAX_INDEX_COLUMNS { return 0, false }
    definition: ^TableDef = &module.tables[table.index]
    for i in 0 ..< definition.index_count {
        index: ^IndexDef = &definition.indexes[i]
        if index.count != len(columns) { continue }
        same: bool = true
        for column, j in columns { if int(index.columns[j]) != column { same = false } }
        if !same { continue }
        if !index.id_known {
            name_buffer: [128]u8
            name: string = indexName(definition, index, name_buffer[:])
            if host_index_id_from_name(raw_data(transmute([]u8)name), uint(len(name)), &index.id) != 0 { return 0, false }
            index.id_known = true
        }
        return index.id, true
    }
    return 0, false       // the table has no such index: give it one in TableOptions
}

// Calls `each` for every row whose indexed columns equal `key` (the BSATN of those columns in the order of the index; for a unique index at most one row). The index has to exist: the primary
// key, a unique column or one of `TableOptions.indexes`. False when there is no such index.
TableFind :: proc(table: Table, columns: []int, key: []u8, user: rawptr, each: proc(user: rawptr, row: ^bsatn.Reader) -> bool) -> bool {
    index, found := indexId(table, columns)
    if !found { return false }
    if len(key) > len(row_buffer) { return false }
    copy(row_buffer[:], key)
    iterator: RowIter
    if host_index_scan_point(index, raw_data(row_buffer[:]), uint(len(key)), &iterator) != 0 { return false }
    return readRows(iterator, user, each)
}

// Deletes the rows whose indexed columns equal `key`; returns how many
TableDeleteBy :: proc(table: Table, columns: []int, key: []u8) -> (deleted: u32, ok: bool) {
    index, found := indexId(table, columns)
    if !found { return 0, false }
    if len(key) > len(row_buffer) { return 0, false }
    copy(row_buffer[:], key)
    status: u16 = host_delete_by_index_point(index, raw_data(row_buffer[:]), uint(len(key)), &deleted)
    return deleted, status == 0          // the count is read after the call that writes it
}

// Replaces the row that has the same value in the unique index `columns` (the primary key is the usual one) with `row`. "" or the text of the error (no such row, a unique value of another row).
TableUpdate :: proc(table: Table, columns: []int, row: []u8) -> string {
    index, found := indexId(table, columns)
    id, table_found := tableId(table)
    if !found || !table_found { return "no such index" }
    if len(row) > len(row_buffer) { return "the row is too big" }
    copy(row_buffer[:], row)
    length: uint = uint(len(row))
    #partial switch Errno(host_update(id, index, raw_data(row_buffer[:]), &length)) {
    case .OK: return ""
    case .NO_SUCH_ROW: return "no row with that key"
    case .INDEX_NOT_UNIQUE: return "the index is not unique"
    case .UNIQUE_ALREADY_EXISTS: return "a row with the same unique value exists"
    case .BSATN_DECODE_ERROR: return "the row does not match the table"
    case: return "the update failed"
    }
}

// Deletes the rows that are equal to `row` (the whole row, BSATN); returns how many
TableDelete :: proc(table: Table, row: []u8) -> (deleted: u32, ok: bool) {
    id, found := tableId(table)
    if !found || len(row) + 4 > len(row_buffer) { return 0, false }
    writer: bsatn.Writer = bsatn.WriterMake(row_buffer[:])
    bsatn.WriteU32(&writer, 1)                  // a relation of one row
    bsatn.WriteRaw(&writer, row)
    bytes: []u8 = bsatn.WriterBytes(&writer)
    status: u16 = host_delete_all_by_eq(id, raw_data(bytes), uint(len(bytes)), &deleted)
    return deleted, status == 0
}

// For a `.SCHEDULE_AT` column: the value as BSATN. A reducer that runs every `microseconds`, or once at a time (microseconds since the Unix epoch).
WriteScheduleInterval :: proc(writer: ^bsatn.Writer, microseconds: i64) {
    bsatn.WriteTag(writer, 0)
    bsatn.WriteI64(writer, microseconds)
}

WriteScheduleTime :: proc(writer: ^bsatn.Writer, timestamp: bsatn.Timestamp) {
    bsatn.WriteTag(writer, 1)
    bsatn.WriteI64(writer, i64(timestamp))
}

// ---- the log ------------------------------------------------------------------------------------------------------------------------------------------------------------------

// A line in the log of the database (what `spacetime logs` and `DatabaseLogs` show)
Log :: proc(level: u8, text: string) {
    host_console_log(level, nil, 0, nil, 0, 0xffffffff, raw_data(transmute([]u8)text), uint(len(text)))
}

// The identity of the database itself
DatabaseIdentity :: proc() -> bsatn.Identity {
    identity: bsatn.Identity
    host_identity(raw_data(identity[:]))
    return identity
}
