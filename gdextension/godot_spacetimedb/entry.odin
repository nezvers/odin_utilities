package godot_spacetimedb

// The entry point that Godot calls when it loads the library (`entry_symbol` of the .gdextension file) and the class `SpacetimeDBClient` (a RefCounted: GDScript makes it with
// `SpacetimeDBClient.new()` and polls it). The class is a table of methods for `odin_utilities/gdextension`; the Godot side (interface, Variants, registration) is that library.

import "core:strings"
import ge "../../gdextension"
import "arena_example"

@(private)
clientOf :: proc(instance: rawptr) -> ^Client {
    return cast(^Client)instance
}

@(private)
textOf :: proc(text: string) -> ge.Value {
    return {kind = .STRING, text = transmute([]u8)text}
}

@(private)
intOf :: proc(number: i64) -> ge.Value {
    return {kind = .INT, number = number}
}

@(private)
boolOf :: proc(value: bool) -> ge.Value {
    return {kind = .BOOL, number = 1 if value else 0}
}

@(private)
spanText :: proc(client: ^Client, span: Span) -> ge.Value {
    return {kind = .STRING, text = spanBytes(client, span)}
}

@(private)
clientToken :: proc(client: ^Client) -> string {
    return strings.clone(string(client.connection.token[:client.connection.token_length]), context.temp_allocator)
}

clientCreate :: proc() -> rawptr {
    client: ^Client = new(Client)
    client.current = -1
    return client
}

clientBind :: proc(instance: rawptr, object: rawptr) {
    clientOf(instance).object = object
}

clientDestroy :: proc(instance: rawptr) {
    clientFree(clientOf(instance))
}

// One table of methods for both flavours: a RefCounted that a script polls, and a Node that polls itself and emits the events as signals
client_methods := [?]ge.Method{
        {"open", {.STRING, .INT, .STRING, .STRING}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return boolOf(clientOpen(clientOf(instance), string(a[0].text), int(a[1].number), string(a[2].text), string(a[3].text)))
        }},
        {"close", {}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            clientClose(clientOf(instance))
            return {}
        }},
        {"is_open", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return boolOf(clientOf(instance).open) }},
        {"subscribe", {.STRING}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return intOf(i64(clientSubscribe(clientOf(instance), string(a[0].text)))) }},
        {"call_reducer", {.STRING, .STRING}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return intOf(i64(clientCallReducer(clientOf(instance), string(a[0].text), string(a[1].text))))
        }},
        {"call_reducer_bytes", {.STRING, .BYTES}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return intOf(i64(clientCallReducerBytes(clientOf(instance), string(a[0].text), a[1].text)))
        }},
        {"event_row_bytes", {}, .BYTES, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            client: ^Client = clientOf(instance)
            hex: []u8 = spanBytes(client, clientEvent(client).row)
            raw: []u8 = make([]u8, len(hex) / 2, context.temp_allocator)
            count, _ := hexDecode(hex, raw)
            return {kind = .BYTES, text = raw[:count]}
        }},
        {"poll", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return intOf(i64(clientPoll(clientOf(instance)))) }},
        {"next_event", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return boolOf(clientNextEvent(clientOf(instance))) }},
        {"event_kind", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return intOf(i64(clientEvent(clientOf(instance)).kind)) }},
        {"event_request", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return intOf(i64(clientEvent(clientOf(instance)).request)) }},
        {"event_ok", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return boolOf(clientEvent(clientOf(instance)).ok) }},
        {"event_table", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return spanText(clientOf(instance), clientEvent(clientOf(instance)).table) }},
        {"event_row", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return spanText(clientOf(instance), clientEvent(clientOf(instance)).row) }},
        {"event_text", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return spanText(clientOf(instance), clientEvent(clientOf(instance)).text) }},
        {"token", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return textOf(clientToken(clientOf(instance))) }},
        {"error", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return textOf(clientOf(instance).error) }},
}

client_class: ge.Class = {
    name = "SpacetimeDBClient",
    parent = "RefCounted",
    create = clientCreate,
    destroy = clientDestroy,
    bind = clientBind,
    methods = client_methods[:],
}

client_signals := [?]ge.Signal{
    {"connected", {.STRING}},                       // our identity (hex)
    {"row_inserted", {.STRING, .BYTES}},            // table, the BSATN bytes of the row
    {"row_deleted", {.STRING, .BYTES}},             // an update is a row_deleted and a row_inserted of the same key, one after the other
    {"subscribed", {.INT}},                         // a subscription is applied (its rows came as row_inserted before): the request id
    {"reducer_result", {.INT, .BOOL, .STRING}},     // request id, ok, the error text
    {"subscription_error", {.STRING}},
    {"disconnected", {.STRING}},                    // the socket was lost; the node reconnects by itself
    {"reconnected", {}},                            // the subscriptions are applied again: their rows come as row_inserted again, clear what you keep
}

// The Node flavour: once a frame it reads the network and tells the script with signals; it closes when it leaves the tree. Do not call `poll` on it.
client_node_class: ge.Class = {
    name = "SpacetimeDBClientNode",
    parent = "Node",
    create = clientCreate,
    destroy = clientDestroy,
    bind = clientBind,
    signals = client_signals[:],
    methods = client_methods[:],
    virtuals = {
        {"_process", proc(instance: rawptr, delta: f64) { clientEmitEvents(clientOf(instance)) }},
        {"_exit_tree", proc(instance: rawptr, delta: f64) { clientClose(clientOf(instance)) }},
    },
}

@(private)
clientEmitEvents :: proc(client: ^Client) {
    if !client.open { return }
    clientPoll(client)
    for clientNextEvent(client) {
        event: Event = clientEvent(client)
        switch event.kind {
        case .NONE:
        case .CONNECTED: ge.Emit(client.object, "connected", {spanText(client, event.text)})
        case .INSERT, .DELETE:
            hex: []u8 = spanBytes(client, event.row)
            raw: []u8 = make([]u8, len(hex) / 2, context.temp_allocator)
            count, _ := hexDecode(hex, raw)
            ge.Emit(client.object, "row_inserted" if event.kind == .INSERT else "row_deleted", {spanText(client, event.table), {kind = .BYTES, text = raw[:count]}})
        case .SUBSCRIBED: ge.Emit(client.object, "subscribed", {intOf(i64(event.request))})
        case .REDUCER: ge.Emit(client.object, "reducer_result", {intOf(i64(event.request)), boolOf(event.ok), spanText(client, event.text)})
        case .SUBSCRIPTION_ERROR: ge.Emit(client.object, "subscription_error", {spanText(client, event.text)})
        case .DISCONNECTED: ge.Emit(client.object, "disconnected", {spanText(client, event.text)})
        case .RECONNECTED: ge.Emit(client.object, "reconnected", {})
        }
        if !client.open { break }               // a handler closed the client
    }
}

classes: [5]^ge.Class = {&client_class, &client_node_class, &lobby_class, &lobby_node_class, &arena_example.arena_class}

// `entry_symbol` of the .gdextension file
@(export)
spacetimedb_entry :: proc "c" (get_proc_address: ge.GetProcAddress, library: ge.Library, initialization: ^ge.Initialization) -> ge.GdBool {
    return ge.Entry(get_proc_address, library, initialization, classes[:])
}
