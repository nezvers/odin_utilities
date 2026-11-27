extends SceneTree

# Run by the test of the library: `godot --headless --path arena_project --script test_arena_node.gd -- <port> <folder of the server>`.
# ArenaClientNode updates itself: a host and a guest node, the script only reacts to signals and moves the guest.

const LOOPBACK := 8
const P2P := 1

var host: ArenaClientNode
var guest: ArenaClientNode
var events := []
var started := 0
var joined := false
var replied := false


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	host = ArenaClientNode.new()
	guest = ArenaClientNode.new()
	root.add_child(host)
	root.add_child(guest)
	host.phase_changed.connect(func(phase: int) -> void: events.append("host phase %d" % phase))
	guest.phase_changed.connect(func(phase: int) -> void: events.append("guest phase %d" % phase))
	host.guest_count_changed.connect(func(count: int) -> void: events.append("guests %d" % count))
	if not host.host("Ada", arguments[1], int(arguments[0]), P2P | LOOPBACK, ""):
		print("FAIL host: ", host.error())
		quit(1)
		return
	started = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 40000:
		print("FAIL timeout: ", events, " ", guest.error(), " ", guest.notice())
		quit(1)
		return true
	if not joined and host.invite() != "":
		joined = true
		if not guest.join(host.invite(), "Bob", LOOPBACK):
			print("FAIL join: ", guest.error())
			quit(1)
	if joined and not replied and guest.needs_reply() and guest.reply() != "":
		replied = true
		host.accept_reply(guest.reply())
	if events.has("guest phase 2") and events.has("guests 1") and events.has("host phase 2"):
		var guest_snapshot := guest.snapshot()
		guest.leave()
		host.leave()
		if guest_snapshot.size() < 20:
			print("FAIL snapshot ", guest_snapshot.size())
			quit(1)
		else:
			print("PASS ", events)
			quit(0)
		return true
	return false
