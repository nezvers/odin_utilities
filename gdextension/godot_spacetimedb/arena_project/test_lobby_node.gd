extends SceneTree

# Run by the test of the library: `godot --headless --path arena_project --script test_lobby_node.gd -- <port> <folder of the server> <the module file>`.
# SpacetimeDBLobbyNode updates itself from the engine's _process: nothing here calls update(). A host and a guest node are in the tree, the script only reacts to their signals.

const LOOPBACK := 8
const P2P := 1

var host: SpacetimeDBLobbyNode
var guest: SpacetimeDBLobbyNode
var events := []
var started := 0
var joined := false
var replied := false
var arguments: PackedStringArray


func _initialize() -> void:
	arguments = OS.get_cmdline_user_args()
	host = SpacetimeDBLobbyNode.new()
	guest = SpacetimeDBLobbyNode.new()
	root.add_child(host)
	root.add_child(guest)
	host.became_ready.connect(func() -> void: events.append("host ready"))
	guest.became_ready.connect(func() -> void: events.append("guest ready"))
	host.guest_joined.connect(func(count: int) -> void: events.append("joined %d" % count))
	if not host.host(arguments[1], "basic", arguments[2], "Ada", int(arguments[0]), P2P | LOOPBACK):
		print("FAIL host: ", host.error())
		quit(1)
	started = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 40000:
		print("FAIL timeout: ", events, " host stage ", host.stage(), " guest stage ", guest.stage(), " ", guest.error(), " ", guest.notice())
		quit(1)
		return true
	if not joined and host.invite() != "":
		joined = true
		if not guest.join(host.invite(), "basic", "Bob", LOOPBACK):
			print("FAIL join: ", guest.error())
			quit(1)
	if joined and not replied and guest.needs_reply() and guest.reply() != "":
		replied = true
		host.accept_reply(guest.reply())
	if events.has("guest ready") and events.has("joined 1"):
		guest.leave()
		host.leave()
		if events.size() == 3 and events.has("host ready"):
			print("PASS")
			quit(0)
		else:
			print("FAIL events ", events)
			quit(1)
		return true
	return false
