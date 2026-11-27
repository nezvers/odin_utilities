extends SceneTree

# Run by the test of the library: `godot --headless --path arena_project --script test_arena.gd -- <port> <folder of the server>`.
# One process plays both sides: a host (its own SpacetimeDB server with the arena module, a p2p invite over loopback) and a guest that joins with the invite code and reaches the host's
# database through the tunnel. The two clients are stepped by this script like the game does it, once per "frame".

const LOOPBACK := 8
const P2P := 1

var host := ArenaClient.new()
var guest := ArenaClient.new()


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	var port := int(arguments[0])
	var root: String = arguments[1]
	var failures := []

	if not host.host("Host", root, port, P2P | LOOPBACK, ""):
		print("FAIL host: ", host.error())
		quit(1)
		return
	if not _until(func() -> bool: return host.invite() != "", 20000):
		print("FAIL no invite, stage ", host.stage(), " ", host.error())
		quit(1)
		return
	var invite := host.invite()
	if host.code_kind(invite) != 2 or host.code_from(invite) != "Host":
		failures.append("the invite is not recognised: kind %d from '%s'" % [host.code_kind(invite), host.code_from(invite)])
	if host.code_kind("") != 0 or host.code_kind("nonsense") != 1 or host.code_kind("maple-otter-22") != 4:
		failures.append("code kinds of an empty text, nonsense and a room name")

	if not guest.join(invite, "Guest", LOOPBACK):
		print("FAIL join: ", guest.error())
		quit(1)
		return
	# no relay: the guest has a reply code that the host has to accept
	if not _until(func() -> bool: return guest.stage() == 4 or guest.stage() == 5, 20000):
		print("FAIL guest stage ", guest.stage(), " ", guest.error(), " ", guest.notice())
		quit(1)
		return
	if not guest.needs_reply():
		failures.append("a guest of an invite with no relay needs a reply")
	if guest.code_kind(guest.reply()) != 3 or not host.accept_reply(guest.reply()):
		failures.append("the host does not accept the reply")
	if not _until(func() -> bool: return guest.phase() == 2 and host.guests() == 1, 30000):
		print("FAIL guest phase ", guest.phase(), " stage ", guest.stage(), " ", guest.error(), " ", guest.notice())
		quit(1)
		return

	# both see two players and the coins
	var both := _until(func() -> bool: return _read(host.snapshot())["players"].size() == 2 and _read(guest.snapshot())["players"].size() == 2 and _read(guest.snapshot())["coins"].size() > 0, 20000)
	if not both:
		print("FAIL the field: host ", _read(host.snapshot()), " guest ", _read(guest.snapshot()))
		quit(1)
		return
	var host_view := _read(host.snapshot())
	var guest_view := _read(guest.snapshot())
	if host_view["me"] == 0 or guest_view["me"] == 0 or host_view["me"] == guest_view["me"]:
		failures.append("the players have no own identity: %s %s" % [host_view["me"], guest_view["me"]])
	if host.game_phase() != 3 or guest.game_phase() != 3:
		failures.append("game phases %d %d" % [host.game_phase(), guest.game_phase()])

	# the guest walks: the host sees it move (through the database)
	var guest_before := _player(host_view, guest_view["me"])
	guest.set_input(1, 0)
	var moved := _until(func() -> bool:
		var now := _player(_read(host.snapshot()), guest_view["me"])
		return not now.is_empty() and absf(now["x"] - guest_before["x"]) > 20.0, 15000)
	guest.set_input(0, 0)
	if not moved:
		failures.append("the host does not see the guest move: %s -> %s" % [guest_before, _player(_read(host.snapshot()), guest_view["me"])])

	# the guest leaves: the host is alone again
	guest.leave()
	if guest.phase() != 0:
		failures.append("leave does not go back to idle")
	if not _until(func() -> bool: return _read(host.snapshot())["players"].size() == 1, 15000):
		failures.append("the host still sees the guest after it left")

	host.leave()
	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL ", failures)
		quit(1)


# Steps both clients until the condition holds or the time is up
func _until(condition: Callable, milliseconds: int) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		host.update(16)
		guest.update(16)
		if condition.call():
			return true
		OS.delay_msec(8)
	return false


func _player(view: Dictionary, id: int) -> Dictionary:
	for player in view["players"]:
		if player["id"] == id:
			return player
	return {}


func _read(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	var result := {"phase": buffer.get_u32()}
	var player_count := buffer.get_u32()
	var coin_count := buffer.get_u32()
	result["picked"] = buffer.get_u32()
	result["me"] = buffer.get_u64()
	var players := []
	for i in player_count:
		var player := {"id": buffer.get_u64(), "x": buffer.get_float(), "y": buffer.get_float(), "score": buffer.get_u32(), "hue": buffer.get_u32()}
		var length := buffer.get_u8()
		player["name"] = buffer.get_data(length)[1].get_string_from_utf8() if length > 0 else ""
		players.append(player)
	var coins := []
	for i in coin_count:
		buffer.get_u64()
		coins.append(Vector2(buffer.get_float(), buffer.get_float()))
	result["players"] = players
	result["coins"] = coins
	return result
