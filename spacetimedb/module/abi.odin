package spacetimedb_module

// The host functions that a SpacetimeDB module imports (spacetimedb/SpacetimeDB/crates/bindings-sys/src/lib.rs, `spacetime_10.0`): the datastore (tables and their rows by BSATN), the bytes that
// come in (the arguments of a reducer) and go out (the description of the module, an error message), and the log. All of them take and return numbers and pointers into the linear memory of
// the module; the ones that return a u16 return 0 for success and an `Errno` otherwise. A module is built for `freestanding_wasm32`, where `uint` is 32 bits like `usize` of the ABI.

foreign import spacetime "spacetime_10.0"

Errno :: enum u16 {
    OK = 0,
    HOST_CALL_FAILURE = 1,
    NOT_IN_TRANSACTION = 2,
    BSATN_DECODE_ERROR = 3,
    NO_SUCH_TABLE = 4,
    NO_SUCH_INDEX = 5,
    NO_SUCH_ITER = 6,
    NO_SUCH_CONSOLE_TIMER = 7,
    NO_SUCH_BYTES = 8,
    NO_SPACE = 9,
    BUFFER_TOO_SMALL = 11,
    UNIQUE_ALREADY_EXISTS = 12,
    SCHEDULE_AT_DELAY_TOO_LONG = 13,
    INDEX_NOT_UNIQUE = 14,
    NO_SUCH_ROW = 15,
}

TableId :: distinct u32
IndexId :: distinct u32
BytesSource :: distinct u32
BytesSink :: distinct u32
RowIter :: distinct u32

LOG_ERROR :: u8(0)
LOG_WARN :: u8(1)
LOG_INFO :: u8(2)
LOG_DEBUG :: u8(3)
LOG_TRACE :: u8(4)
LOG_PANIC :: u8(101)

foreign import spacetime_5 "spacetime_10.5"

@(default_calling_convention = "c")
foreign spacetime_5 {
    @(link_name = "datastore_clear")
    host_clear :: proc(table: TableId, out: ^u64) -> u16 ---
}

// Functions of later versions of the ABI are their own import modules: a module that does not use them does not import them, so it still loads on an older server
foreign import spacetime_4 "spacetime_10.4"

@(default_calling_convention = "c")
foreign spacetime_4 {
    @(link_name = "datastore_index_scan_point_bsatn")
    host_index_scan_point :: proc(index: IndexId, point: [^]u8, point_length: uint, out: ^RowIter) -> u16 ---
    @(link_name = "datastore_delete_by_index_scan_point_bsatn")
    host_delete_by_index_point :: proc(index: IndexId, point: [^]u8, point_length: uint, out: ^u32) -> u16 ---
}

@(default_calling_convention = "c")
foreign spacetime {
    @(link_name = "datastore_update_bsatn")
    host_update :: proc(table: TableId, index: IndexId, row: [^]u8, row_length: ^uint) -> u16 ---
    @(link_name = "table_id_from_name")
    host_table_id_from_name :: proc(name: [^]u8, name_length: uint, out: ^TableId) -> u16 ---
    @(link_name = "index_id_from_name")
    host_index_id_from_name :: proc(name: [^]u8, name_length: uint, out: ^IndexId) -> u16 ---
    @(link_name = "datastore_table_row_count")
    host_table_row_count :: proc(table: TableId, out: ^u64) -> u16 ---
    @(link_name = "datastore_table_scan_bsatn")
    host_table_scan :: proc(table: TableId, out: ^RowIter) -> u16 ---
    @(link_name = "row_iter_bsatn_advance")
    host_row_iter_advance :: proc(iterator: RowIter, buffer: [^]u8, buffer_length: ^uint) -> i16 ---
    @(link_name = "row_iter_bsatn_close")
    host_row_iter_close :: proc(iterator: RowIter) -> u16 ---
    @(link_name = "datastore_insert_bsatn")
    host_insert :: proc(table: TableId, row: [^]u8, row_length: ^uint) -> u16 ---
    @(link_name = "datastore_delete_all_by_eq_bsatn")
    host_delete_all_by_eq :: proc(table: TableId, relation: [^]u8, relation_length: uint, out: ^u32) -> u16 ---
    @(link_name = "bytes_sink_write")
    host_bytes_sink_write :: proc(sink: BytesSink, buffer: [^]u8, buffer_length: ^uint) -> u16 ---
    @(link_name = "bytes_source_read")
    host_bytes_source_read :: proc(source: BytesSource, buffer: [^]u8, buffer_length: ^uint) -> i16 ---
    @(link_name = "console_log")
    host_console_log :: proc(level: u8, target: [^]u8, target_length: uint, filename: [^]u8, filename_length: uint, line: u32, text: [^]u8, text_length: uint) ---
    @(link_name = "identity")
    host_identity :: proc(out: [^]u8) ---
}
