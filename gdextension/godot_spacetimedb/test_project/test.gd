extends SceneTree

# Run by the test of the library: `godot --headless --path test_project --script test.gd -- <port>`.
# A SpacetimeDB server is already running on the port with the module `basic` (a table `person`, a reducer `add(name)`).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0])
	var client := SpacetimeDBClient.new()
	if not client.open("127.0.0.1", port, "odin-session", ""):
		print("FAIL open: ", client.error())
		quit(1)
		return

	var identity := ""
	var rows := []
	var subscribed := false
	var called := 0
	var reducer_ok := false
	var refused := false
	var deadline := Time.get_ticks_msec() + 8000
	client.subscribe("SELECT * FROM person")
	while Time.get_ticks_msec() < deadline and not (reducer_ok and refused and rows.size() >= 2):
		client.poll()
		while client.next_event():
			match client.event_kind():
				1:
					identity = client.event_text()
				2:
					rows.append([client.event_table(), client.event_row(), client.event_row_bytes()])
				4:
					if not subscribed:
						subscribed = true
						called = client.call_reducer("add", _string_arguments("Ada"))
						client.call_reducer("add", _string_arguments(""))
						client.call_reducer_bytes("add", _string_bytes("Grace"))
				5:
					if client.event_ok():
						reducer_ok = true
					else:
						refused = true
						print("refused: ", client.event_text())
		OS.delay_msec(5)

	var failures := []
	if identity.length() != 64:
		failures.append("identity: " + identity)
	if called == 0:
		failures.append("the reducer was not called")
	if not reducer_ok:
		failures.append("no ok result from the reducer")
	if not refused:
		failures.append("the empty name was not refused")
	if rows.size() < 2 or rows[0][0] != "person" or rows[0][1] != "03000000416461":
		failures.append("rows: " + str(rows))
	elif rows[0][2] != "03000000416461".hex_decode() or rows[1][2] != _string_bytes("Grace"):
		failures.append("bytes of the rows: " + str(rows))
	client.close()
	if client.is_open():
		failures.append("close did not close")
	if failures.is_empty():
		print("PASS ", rows)
		quit(0)
	else:
		print("FAIL ", failures)
		quit(1)


# BSATN of a string: a u32 length, the bytes, written as hex
func _string_arguments(text: String) -> String:
	var buffer := StreamPeerBuffer.new()
	var bytes := text.to_utf8_buffer()
	buffer.put_u32(bytes.size())
	buffer.put_data(bytes)
	return buffer.data_array.hex_encode()


func _string_bytes(text: String) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	var bytes := text.to_utf8_buffer()
	buffer.put_u32(bytes.size())
	buffer.put_data(bytes)
	return buffer.data_array
