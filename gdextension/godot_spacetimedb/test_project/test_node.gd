extends SceneTree

# Run by the test of the library: `godot --headless --path test_project --script test_node.gd -- <port>`.
# SpacetimeDBClientNode polls itself from _process and tells the script with signals; nothing here calls poll() or next_event().

var client: SpacetimeDBClientNode
var log := []
var rows := []
var reducer_ok := false
var identity := ""
var started := 0


func _initialize() -> void:
	var port := int(OS.get_cmdline_user_args()[0])
	client = SpacetimeDBClientNode.new()
	root.add_child(client)
	client.connected.connect(func(id: String) -> void: identity = id)
	client.row_inserted.connect(func(table: String, row: PackedByteArray) -> void: rows.append([table, row]))
	client.subscribed.connect(func(_request: int) -> void:
		log.append("subscribed")
		client.call_reducer_bytes("add", _string_bytes("Node")))
	client.reducer_result.connect(func(_request: int, ok: bool, _error: String) -> void: reducer_ok = ok)
	if not client.open("127.0.0.1", port, "odin-session", ""):
		print("FAIL open: ", client.error())
		quit(1)
		return
	client.subscribe("SELECT * FROM person")
	started = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var seen := false
	for row in rows:
		seen = seen or row[1] == _string_bytes("Node")
	if reducer_ok and seen and identity.length() == 64 and log == ["subscribed"]:
		client.close()
		print("PASS ", rows.size(), " rows")
		quit(0)
		return true
	if Time.get_ticks_msec() - started > 10000:
		print("FAIL timeout: identity ", identity.length(), " log ", log, " ok ", reducer_ok, " rows ", rows.size())
		quit(1)
		return true
	return false


func _string_bytes(text: String) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	var bytes := text.to_utf8_buffer()
	buffer.put_u32(bytes.size())
	buffer.put_data(bytes)
	return buffer.data_array
