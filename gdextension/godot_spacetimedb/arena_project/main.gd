extends Control

# The arena game (odin_utilities/spacetimedb/arena) in Godot. All of the game and the networking is the extension class `ArenaClient`; this script is the windows and the drawing.
#
#   Play solo      starts a SpacetimeDB server with the game module on this computer and plays on it
#   Host a game    the same, and an invite code (and a room name with the free relay) for friends: Copy it and send it
#   Join a game    paste the code or the room name of a host and press Connect
#
# From the command line (the start screen is skipped): `godot --path arena_project -- solo|host|join <code> [name]`, `--relay`, `--internet`, `--port=N`.
# The field is 800 x 600 units, the database moves everybody (the server runs 20 steps a second); WASD or the arrows send the direction you hold.

const FIELD := Vector2(800, 600)
const FIELD_POSITION := Vector2(10, 10)
const PANEL_X := 830.0
const STAGES := ["idle", "looking for the addresses a friend can reach", "reaching the free relay", "asking the relay who hosts the room", "ready", "connected", "failed"]
const GAME_PHASES := ["closed", "connecting", "joining the game", "playing", "connection lost, reconnecting"]
const GOOD := Color(0.35, 0.8, 0.45)
const WARNING := Color(0.95, 0.65, 0.25)
const DIM := Color(0.6, 0.6, 0.65)

enum Screen { MENU, JOIN, STARTING, CONNECTING, PLAYING }

var arena := ArenaClient.new()
var screen := Screen.MENU
var pending := ""                  # what to start in the next frame, so that "Starting..." is drawn first
var pending_code := ""
var flags_value := 0
var _port := 0                      # the port of the server of a host (0: the default)
var hosting := false                # a host that offers an invite (not solo)

var snapshot := {"players": [], "coins": [], "phase": 0, "me": 0, "picked": 0}
var frames := 0
var told := false                  # the invite and the reply were printed to the console (for two windows started from a command line)

# the screens
var menu_box: VBoxContainer
var join_box: VBoxContainer
var wait_box: VBoxContainer
var side_box: VBoxContainer
var field: Control

var name_edit: LineEdit
var relay_check: CheckBox
var internet_check: CheckBox
var message_label: Label
var code_edit: LineEdit
var code_status: Label
var wait_label: Label
var wait_notice: Label
var reply_box: VBoxContainer
var reply_edit: LineEdit
var scoreboard: Label
var host_box: VBoxContainer
var invite_button: Button
var room_button: Button
var friends_label: Label
var accept_edit: LineEdit
var accept_status: Label
var game_status: Label


func _ready() -> void:
	_build()
	var arguments := OS.get_cmdline_user_args()
	var name := "player"
	var port := 0
	for argument in arguments:
		if argument.begins_with("--port="):
			port = int(argument.substr(7))
		elif argument == "--relay":
			relay_check.button_pressed = true
		elif argument == "--internet":
			internet_check.button_pressed = true
	var words: Array[String] = []
	for argument in arguments:
		if not argument.begins_with("--"):
			words.append(argument)
	if words.size() > 0:
		match words[0]:
			"solo", "host":
				name = words[1] if words.size() > 1 else name
				name_edit.text = name
				_start(words[0], "", port)
			"join":
				if words.size() > 1:
					name = words[2] if words.size() > 2 else name
					name_edit.text = name
					_start("join", words[1], port)


func _exit_tree() -> void:
	arena.leave()


func _process(delta: float) -> void:
	if pending != "":
		var what := pending
		pending = ""
		_launch(what)
		return
	arena.update(int(delta * 1000.0))
	match arena.phase():
		1:
			_show(Screen.CONNECTING)
			wait_label.text = "Connecting: " + STAGES[arena.stage()]
			wait_notice.text = arena.notice()
			reply_box.visible = arena.stage() == 4 and arena.needs_reply()
			if reply_box.visible and not told:
				told = true
				print("The host needs this reply code (paste it in its window):
", arena.reply())
			if reply_box.visible and reply_edit.text != arena.reply():
				reply_edit.text = arena.reply()
		2:
			if screen != Screen.PLAYING:
				_show(Screen.PLAYING)
			frames += 1
			arena.set_input(_held().x, _held().y)
			snapshot = _read(arena.snapshot())
			_update_side()
			if hosting and not told and arena.invite() != "":
				told = true
				print("Give this code to your friends (godot --path arena_project -- join <code>):
", arena.invite())
				if arena.room() != "":
					print("Or the room name: ", arena.room())
			field.queue_redraw()
		3:
			_fail(arena.error())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and screen != Screen.MENU:
		_back("")


# ---- starting and leaving ---------------------------------------------------------------------------------------------------------------------------------------

func _start(what: String, code: String, port: int = 0) -> void:
	told = false
	pending = what
	pending_code = code
	flags_value = 0
	if relay_check.button_pressed:
		flags_value |= 2
	if internet_check.button_pressed:
		flags_value |= 4
	if what == "host":
		flags_value |= 1
	hosting = what == "host"
	_port = port
	_show(Screen.STARTING)


# The server of a host starts here: a second or two, during which the window does not move
func _launch(what: String) -> void:
	var player := name_edit.text.strip_edges()
	if player == "":
		player = "player"
	var started := false
	if what == "join":
		started = arena.join(pending_code, player, flags_value)
	else:
		var root := OS.get_user_data_dir() + "/arena_server"
		started = arena.host(player, root, _port, flags_value, _module_path())
	if not started:
		_fail(arena.error())
	elif what == "join":
		_show(Screen.CONNECTING)
	else:
		_show(Screen.PLAYING)


# The module of the game that the server publishes: the one of the library unless a copy is next to the project (an exported game ships it)
func _module_path() -> String:
	var copy := ProjectSettings.globalize_path("res://arena-odin.wasm")
	return copy if FileAccess.file_exists("res://arena-odin.wasm") else ""


func _fail(text: String) -> void:
	arena.leave()
	_back("Could not start: " + text)


func _back(text: String) -> void:
	arena.leave()
	snapshot = {"players": [], "coins": [], "phase": 0, "me": 0, "picked": 0}
	message_label.text = text
	message_label.add_theme_color_override("font_color", WARNING)
	_show(Screen.MENU)


func _show(next: Screen) -> void:
	screen = next
	menu_box.visible = next == Screen.MENU
	join_box.visible = next == Screen.JOIN
	wait_box.visible = next == Screen.STARTING or next == Screen.CONNECTING
	side_box.visible = next == Screen.PLAYING
	field.visible = next == Screen.PLAYING
	if next == Screen.STARTING:
		wait_label.text = "Starting the server..."
		wait_notice.text = ""
		reply_box.visible = false


# ---- input -----------------------------------------------------------------------------------------------------------------------------------------------------

func _held() -> Vector2i:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return Vector2i.ZERO
	var x := int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var y := int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	return Vector2i(x, y)


# ---- the snapshot of the extension -------------------------------------------------------------------------------------------------------------------------------

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
		coins.append(Vector2(0, 0))
		var id := buffer.get_u64()
		coins[i] = Vector2(buffer.get_float(), buffer.get_float())
	result["players"] = players
	result["coins"] = coins
	return result


# ---- drawing -----------------------------------------------------------------------------------------------------------------------------------------------------

func _draw_field() -> void:
	field.draw_rect(Rect2(Vector2.ZERO, FIELD), Color(0.09, 0.1, 0.14))
	field.draw_rect(Rect2(Vector2.ZERO, FIELD), Color(0.3, 0.32, 0.4), false, 2.0)
	if snapshot["phase"] != 3:
		var text: String = GAME_PHASES[snapshot["phase"]] if snapshot["phase"] < GAME_PHASES.size() else ""
		field.draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Joining the game: " + text if snapshot["phase"] == 2 else text.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, DIM)
		return
	for coin in snapshot["coins"]:
		field.draw_circle(coin, 7.0, Color(1.0, 0.82, 0.25))
		field.draw_arc(coin, 7.0, 0, TAU, 16, Color(0.6, 0.45, 0.1), 1.5)
	for player in snapshot["players"]:
		var position := Vector2(player["x"], player["y"])
		var color := Color.from_hsv(float(player["hue"]) / 255.0, 0.65, 0.95)
		field.draw_circle(position, 14.0, color)
		if player["id"] == snapshot["me"]:
			field.draw_arc(position, 17.0, 0, TAU, 28, Color.WHITE, 2.5)
		field.draw_string(ThemeDB.fallback_font, position + Vector2(-40, -22), player["name"], HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(0.9, 0.9, 0.95))


func _update_side() -> void:
	var players: Array = snapshot["players"].duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var lines := PackedStringArray()
	for player in players:
		lines.append("%s%s   %d" % ["> " if player["id"] == snapshot["me"] else "   ", player["name"], player["score"]])
	scoreboard.text = "Scoreboard\n" + "\n".join(lines)
	var phase: int = snapshot["phase"]
	game_status.text = GAME_PHASES[phase] if phase < GAME_PHASES.size() else ""
	host_box.visible = hosting
	if host_box.visible:
		var ready := arena.invite() != ""
		invite_button.disabled = not ready
		invite_button.text = "Copy the invite code" if ready else "Making the invite..."
		room_button.visible = arena.room() != ""
		room_button.text = "Copy the room name (" + arena.room() + ")"
		var guests := arena.guests()
		friends_label.text = "%d friend%s connected" % [guests, "" if guests == 1 else "s"]
		if ready and not arena.relay_ready():
			accept_edit.get_parent().visible = true
		else:
			accept_edit.get_parent().visible = false
		var kind := arena.code_kind(accept_edit.text)
		accept_status.text = _kind_text(kind, accept_edit.text, true)
		accept_status.add_theme_color_override("font_color", GOOD if kind == 3 else (DIM if kind == 0 else WARNING))


func _kind_text(kind: int, text: String, reply_wanted: bool) -> String:
	match kind:
		0:
			return "Paste the reply code of a friend." if reply_wanted else "Paste the code or room name of a host."
		1:
			return "That is not a code."
		2:
			return "That is an invite: " + ("the host needs the REPLY of the friend, not an invite." if reply_wanted else "invite code of " + _from(text) + ".")
		3:
			return "Reply code of " + _from(text) + ("." if reply_wanted else ": that goes to the host, not here.")
		4:
			return "Room " + _from(text) + ": the relay will find the host." if not reply_wanted else "A room name is for joining, not for a reply."
	return ""


func _from(text: String) -> String:
	var from := arena.code_from(text)
	return from if from != "" else "a friend"


# ---- the windows -------------------------------------------------------------------------------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.07, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# the start screen
	menu_box = _column(Vector2(380, 40), 420)
	_label(menu_box, "Arena", 40)
	_label(menu_box, "A small multiplayer game: the world is a SpacetimeDB database written in Odin.", 14, DIM)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.text = "player"
	name_edit.max_length = 24
	menu_box.add_child(name_edit)
	relay_check = CheckBox.new()
	relay_check.text = "Free relay: friends join with one code (host)"
	menu_box.add_child(relay_check)
	internet_check = CheckBox.new()
	internet_check.text = "Public address: friends on other networks"
	menu_box.add_child(internet_check)
	_button(menu_box, "Play solo", func() -> void: _start("solo", ""))
	_button(menu_box, "Host a game", func() -> void: _start("host", ""))
	_button(menu_box, "Join a game", func() -> void:
		code_edit.text = ""
		_show(Screen.JOIN))
	message_label = _label(menu_box, "", 14, DIM)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# the code form of a guest
	join_box = _column(Vector2(280, 80), 620)
	_label(join_box, "Join a game", 32)
	_label(join_box, "Paste the invite code or the room name of the host.", 14, DIM)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "invite code or room name"
	code_edit.text_changed.connect(func(text: String) -> void: _update_code_status())
	join_box.add_child(code_edit)
	_button(join_box, "Paste", func() -> void:
		code_edit.text = DisplayServer.clipboard_get().strip_edges()
		_update_code_status())
	code_status = _label(join_box, "", 14, DIM)
	_button(join_box, "Connect", func() -> void:
		var kind := arena.code_kind(code_edit.text)
		if kind == 2 or kind == 4:
			_start("join", code_edit.text.strip_edges())
		else:
			code_status.text = "Paste an invite code or a room name first.")
	_button(join_box, "Back", func() -> void: _show(Screen.MENU))

	# starting and connecting
	wait_box = _column(Vector2(280, 120), 620)
	wait_label = _label(wait_box, "", 24)
	wait_notice = _label(wait_box, "", 14, WARNING)
	wait_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply_box = VBoxContainer.new()
	wait_box.add_child(reply_box)
	_label(reply_box, "This code names no relay, so the host needs a reply code from you. Send it to the host:", 14, WARNING).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply_edit = LineEdit.new()
	reply_edit.editable = false
	reply_box.add_child(reply_edit)
	_button(reply_box, "Copy the reply code", func() -> void: DisplayServer.clipboard_set(arena.reply()))
	_button(wait_box, "Cancel", func() -> void: _back(""))

	# the field and the panel of a game
	field = Control.new()
	field.position = FIELD_POSITION
	field.size = FIELD
	field.draw.connect(_draw_field)
	add_child(field)
	side_box = VBoxContainer.new()
	side_box.position = Vector2(PANEL_X, 10)
	side_box.custom_minimum_size = Vector2(330, 0)
	side_box.add_theme_constant_override("separation", 8)
	add_child(side_box)
	scoreboard = _label(side_box, "", 16)
	game_status = _label(side_box, "", 13, DIM)
	host_box = VBoxContainer.new()
	host_box.add_theme_constant_override("separation", 6)
	side_box.add_child(host_box)
	_label(host_box, "Friends", 18)
	invite_button = _button(host_box, "Copy the invite code", func() -> void: DisplayServer.clipboard_set(arena.invite()))
	room_button = _button(host_box, "Copy the room name", func() -> void: DisplayServer.clipboard_set(arena.room()))
	friends_label = _label(host_box, "", 14, GOOD)
	var accept_row := VBoxContainer.new()
	host_box.add_child(accept_row)
	_label(accept_row, "No relay: a friend sends back a reply code. Paste it here.", 13, DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	accept_edit = LineEdit.new()
	accept_edit.placeholder_text = "reply code"
	accept_row.add_child(accept_edit)
	_button(accept_row, "Paste", func() -> void: accept_edit.text = DisplayServer.clipboard_get().strip_edges())
	_button(accept_row, "Accept the reply", func() -> void:
		if arena.accept_reply(accept_edit.text):
			accept_edit.text = ""
		else:
			accept_status.text = "That is not a reply code.")
	accept_status = _label(accept_row, "", 13, DIM)
	accept_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(side_box, "Leave (Escape)", func() -> void: _back(""))
	_show(Screen.MENU)


func _update_code_status() -> void:
	var kind := arena.code_kind(code_edit.text)
	code_status.text = _kind_text(kind, code_edit.text, false)
	code_status.add_theme_color_override("font_color", GOOD if kind == 2 or kind == 4 else (DIM if kind == 0 else WARNING))


func _column(position_value: Vector2, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = position_value
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	return box


func _label(parent: Control, text: String, size: int, color: Color = Color(0.92, 0.92, 0.96)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
