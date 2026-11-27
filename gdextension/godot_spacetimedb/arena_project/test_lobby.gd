extends SceneTree

# Run by the test of the library: `godot --headless --path arena_project --script test_lobby.gd -- <port> <folder of the server> <the module file>`.
# Nothing of this is the arena: SpacetimeDBLobby (host and join, the p2p side) and SpacetimeDBClient (the database) are the generic classes, the module is the `basic` example (a table `person`, a reducer
# `add(name)`) published as the database "basic". One process plays both sides: a host, and a guest that joins with the invite code, reaches the host's database through the tunnel and adds a person
# that the host sees.

const LOOPBACK := 8
const P2P := 1

var host := SpacetimeDBLobby.new()
var guest := SpacetimeDBLobby.new()
var host_client := SpacetimeDBClient.new()
var guest_client := SpacetimeDBClient.new()


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	var port := int(arguments[0])
	var root: String = arguments[1]
	var module: String = arguments[2]
	var failures := []

	if not host.host(root, "basic", module, "Ada", port, P2P | LOOPBACK):
		print("FAIL host: ", host.error())
		quit(1)
		return
	if not host.ready() or host.database() != "basic" or host.endpoint_port() != port:
		failures.append("a host is ready with its server: ready %s database %s port %d" % [host.ready(), host.database(), host.endpoint_port()])
	if not _until(func() -> bool: return host.invite() != "", 20000):
		print("FAIL no invite, stage ", host.stage(), " ", host.error())
		quit(1)
		return
	var invite := host.invite()
	if host.code_kind(invite) != 2 or host.code_from(invite) != "Ada":
		failures.append("the invite is not recognised: kind %d from '%s'" % [host.code_kind(invite), host.code_from(invite)])

	if guest.join("not a code", "basic", "X", 0) or not guest.failed() or guest.error() == "":
		failures.append("a bad code should fail with a text")
	if not guest.join(invite, "basic", "Bob", LOOPBACK):
		print("FAIL join: ", guest.error())
		quit(1)
		return
	if guest.ready():
		failures.append("a guest is not ready before the tunnel is open")
	if not _until(func() -> bool: return guest.stage() == 4 or guest.stage() == 5, 20000):
		print("FAIL guest stage ", guest.stage(), " ", guest.error(), " ", guest.notice())
		quit(1)
		return
	if not guest.needs_reply() or not host.accept_reply(guest.reply()):
		failures.append("the reply of the guest is not accepted")
	if not _until(func() -> bool: return guest.ready() and host.guests() == 1, 30000):
		print("FAIL guest ready ", guest.ready(), " stage ", guest.stage(), " ", guest.error(), " ", guest.notice())
		quit(1)
		return

	# any game connects a client to the endpoint of its lobby: the host's own server, the guest's tunnel (a different port)
	if guest.endpoint_port() == host.endpoint_port():
		failures.append("the guest talks to a local port of its tunnel")
	if not host_client.open(host.endpoint_host(), host.endpoint_port(), host.database(), ""):
		failures.append("the host client does not open: " + host_client.error())
	if not guest_client.open(guest.endpoint_host(), guest.endpoint_port(), guest.database(), ""):
		failures.append("the guest client does not open through the tunnel: " + guest_client.error())
	host_client.subscribe("SELECT * FROM person")
	guest_client.subscribe("SELECT * FROM person")
	var guest_subscribed := false
	var host_rows := []
	var guest_rows := []
	var reducer_ok := false
	var done := _until(func() -> bool:
		host_client.poll()
		while host_client.next_event():
			if host_client.event_kind() == 2:
				host_rows.append(host_client.event_row_bytes())
		guest_client.poll()
		while guest_client.next_event():
			match guest_client.event_kind():
				2:
					guest_rows.append(guest_client.event_row_bytes())
				4:
					if not guest_subscribed:
						guest_subscribed = true
						guest_client.call_reducer_bytes("add", _string_bytes("Grace"))
				5:
					reducer_ok = reducer_ok or guest_client.event_ok()
		return reducer_ok and host_rows.size() >= 1 and guest_rows.size() >= 1, 20000)
	if not done:
		failures.append("the person added by the guest does not reach both: ok %s host %s guest %s" % [reducer_ok, host_rows, guest_rows])
	elif host_rows[0] != _string_bytes("Grace"):
		failures.append("the host sees another row: %s" % [host_rows[0]])

	guest_client.close()
	host_client.close()
	guest.leave()
	host.leave()
	if guest.ready() or host.ready():
		failures.append("leave does not reset the lobbies")
	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL ", failures)
		quit(1)


func _until(condition: Callable, milliseconds: int) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		host.update()
		guest.update()
		if condition.call():
			return true
		OS.delay_msec(8)
	return false


# BSATN of a string: a u32 length and the bytes
func _string_bytes(text: String) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	var bytes := text.to_utf8_buffer()
	buffer.put_u32(bytes.size())
	buffer.put_data(bytes)
	return buffer.data_array
