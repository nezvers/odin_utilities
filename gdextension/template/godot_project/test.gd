extends SceneTree

# Run by the test of the template: `godot --headless --path godot_project --script test.gd`

func _init() -> void:
	var failures := []
	var counter := Counter.new()
	_check(failures, counter.add(5) == 5, "add 5")
	_check(failures, counter.add(7) == 12, "add 7")
	_check(failures, counter.get() == 12, "get")
	var seen := []
	counter.changed.connect(func(total: int) -> void: seen.append(total))
	counter.add(3)
	_check(failures, seen == [15], "the changed signal carries the total: %s" % [seen])
	var notes := []
	counter.noted.connect(func(text: String, flag: bool, bytes: PackedByteArray) -> void: notes.append([text, flag, bytes.size()]))
	counter.note("héllo")
	_check(failures, notes == [["héllo", true, 6]], "the noted signal carries a String, a bool and bytes: %s" % [notes])
	_check(failures, counter.has_signal("changed") and counter.get_signal_list().size() >= 2, "the signals are registered")
	_check(failures, counter.half(5.0) == 2.5, "half")
	_check(failures, counter.flip(Vector2(1, 2)) == Vector2(2, 1), "flip a Vector2")
	_check(failures, counter.sum3(Vector3(1, 2, 3)) == 6.0, "sum3")
	_check(failures, counter.rotate3(Vector3(1, 2, 3)) == Vector3(3, 1, 2), "a Vector3 result")
	var moves := []
	counter.moved.connect(func(distance: float, direction: Vector2) -> void: moves.append([distance, direction]))
	counter.move(1.5, Vector2(3, 4))
	_check(failures, moves == [[1.5, Vector2(3, 4)]], "the moved signal carries a float and a Vector2: %s" % [moves])
	var untyped: Variant = counter
	_check(failures, untyped.call("half", 9.0) == 4.5, "half through a Variant call")
	counter.total = 40
	_check(failures, counter.total == 40 and counter.get() == 40, "the property total writes and reads")
	_check(failures, counter.get_property_list().any(func(p: Dictionary) -> bool: return p.name == "total"), "the property is listed")
	var main_font := SystemFont.new()
	var fallback := SystemFont.new()
	_check(failures, counter.set_fallbacks(main_font, fallback) == 1 and main_font.fallbacks.size() == 1 and main_font.fallbacks[0] == fallback, "a typed Array argument reaches the engine")
	_check(failures, counter.call_back(func(x: int) -> int: return x + 1, 4) == 5, "a lambda is called through a Callable argument")
	_check(failures, counter.call_back(Callable(self, "_double"), 21) == 42, "a method Callable")
	_check(failures, counter.fire(1) == -1, "no callback kept yet")
	var captured := [0]
	counter.on_total(func(x: int) -> int:
		captured[0] += x
		return captured[0])
	_check(failures, counter.fire(3) == 3 and counter.fire(4) == 7 and captured[0] == 7, "a kept Callable is called later: %s" % [captured])
	counter.on_total(func(x: int) -> int: return x * 10)
	var probe := RefCounted.new()
	counter.on_total(func(x: int) -> int: return probe.get_reference_count())
	var held: int = counter.fire(0)
	counter.on_total(func(x: int) -> int: return x * 10)
	var released: int = probe.get_reference_count()
	_check(failures, released == 1 and held > released, "the kept Callable holds what the lambda captured until it is replaced: %s then %s" % [held, released])
	_check(failures, counter.fire(5) == 50 and captured[0] == 7, "a new callback replaces the kept one")
	counter.reset()
	var settings := Settings.new()
	settings.title = "fast"
	settings.speed = 2.5
	var inner := Settings.new()
	inner.title = "inner"
	settings.child = inner
	var references: int = inner.get_reference_count()
	_check(failures, references == 2, "a Resource property keeps a reference: %s" % [references])
	_check(failures, settings.child == inner, "and gives the object back")
	_check(failures, settings.get_property_list().any(func(p: Dictionary) -> bool: return p.name == "child" and p.class_name == &"Settings" and p.hint == PROPERTY_HINT_RESOURCE_TYPE), "the property names its class")
	var extra := Settings.new()
	extra.title = "extra"
	var parts: Array[Settings] = [inner, extra]
	settings.parts = parts
	parts = []     # the script keeps no reference of its own: the counts below are the ones of the extension
	var kept_parts: Array[Settings] = settings.parts
	_check(failures, kept_parts.size() == 2 and kept_parts[1].title == "extra" and kept_parts.is_typed(), "an Array[Settings] property: %s" % [kept_parts])
	kept_parts = []
	var part_references: int = extra.get_reference_count()
	_check(failures, part_references == 2, "the elements are kept: %s" % [part_references])
	var settings_path := "user://odin_template_settings.tres"
	_check(failures, settings is Resource and ResourceSaver.save(settings, settings_path) == OK, "a Resource of the extension is saved")
	var loaded: Resource = ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(failures, loaded != null and loaded.title == "fast" and loaded.speed == 2.5, "and loaded again with its properties: %s" % [loaded])
	_check(failures, FileAccess.get_file_as_string(settings_path).contains('type="Settings"'), "the file names the class")
	_check(failures, loaded != null and loaded.child != null and loaded.child.title == "inner", "a nested Resource is saved with it: %s" % [loaded.child if loaded else null])
	_check(failures, loaded != null and loaded.parts.size() == 2 and loaded.parts[1].title == "extra", "the typed Array is saved and loaded: %s" % [loaded.parts if loaded else null])
	DirAccess.remove_absolute(settings_path)
	settings.parts = []
	_check(failures, extra.get_reference_count() == 1, "an emptied Array gives the references back: %s" % [extra.get_reference_count()])
	settings.child = null
	_check(failures, inner.get_reference_count() == 1, "setting null gives the reference back: %s" % [inner.get_reference_count()])
	var hints := {}
	for p in counter.get_property_list():
		hints[p.name] = [p.hint, p.hint_string]
	_check(failures, hints.get("mode") == [PROPERTY_HINT_ENUM, "Off,Low:5,High:10"], "the enum hint reaches the inspector: %s" % [hints.get("mode")])
	_check(failures, hints.get("gain") == [PROPERTY_HINT_RANGE, "0,1,0.05"], "the range hint: %s" % [hints.get("gain")])
	_check(failures, hints.get("total") == [PROPERTY_HINT_NONE, ""], "a property without a hint: %s" % [hints.get("total")])
	var names: Array = counter.get_property_list().map(func(p: Dictionary) -> String: return p.name)
	var at_group: int = names.find("Mixer")
	_check(failures, at_group >= 0 and names.find("mode") == at_group + 1 and names.find("gain") == at_group + 2, "the group Mixer comes before its properties: %s" % [names])
	_check(failures, names.find("total") < at_group, "total is outside of the group: %s" % [names])
	_check(failures, Counter.Mode.HIGH == 10 and Counter.LOW == 5 and Counter.LIMIT == 99, "the constants of the class")
	_check(failures, ClassDB.class_get_enum_constants("Counter", "Mode") == PackedStringArray(["OFF", "LOW", "HIGH"]), "the enum lists its members: %s" % [ClassDB.class_get_enum_constants("Counter", "Mode")])
	counter.mode = Counter.Mode.LOW
	_check(failures, Counter.twice(21) == 42 and counter.twice(4) == 8, "a static method on the class and on an object")
	counter.gain = 0.25
	_check(failures, counter.mode == 5 and counter.gain == 0.25, "the enum and range properties work")
	counter.mode = 0
	counter.gain = 0.0
	_check(failures, counter.double_all([1, 2.5, "ab", true]) == [2, 5.0, "ab!", true], "an Array in and out: %s" % [counter.double_all([1, 2.5, "ab", true])])
	_check(failures, counter.double_all([]) == [], "an empty Array")
	var annotated: Dictionary = counter.annotate({"a": 1, "b": "two", "c": 3.5})
	_check(failures, annotated == {"a": 1, "b": "two", "c": 3.5, "count": 3}, "a Dictionary in and out: %s" % [annotated])
	var listed := []
	counter.listed.connect(func(items: Array, entries: Dictionary) -> void: listed.append([items, entries]))
	counter.list([1, "x"], {"k": 7})
	_check(failures, listed == [[[1, "x"], {"k": 7}]], "the listed signal carries an Array and a Dictionary: %s" % [listed])
	_check(failures, counter.prefix_sums(PackedInt64Array([1, 2, 3, 4])) == PackedInt64Array([1, 3, 6, 10]), "PackedInt64Array in and out")
	_check(failures, counter.halve_all(PackedFloat64Array([1.0, 5.0])) == PackedFloat64Array([0.5, 2.5]), "PackedFloat64Array in and out")
	_check(failures, counter.shout_all(PackedStringArray(["ab", "zoë", ""])) == PackedStringArray(["AB", "ZOË", ""]), "PackedStringArray in and out")
	_check(failures, counter.double_ints32(PackedInt32Array([1, -2, 300000])) == PackedInt32Array([2, -4, 600000]), "PackedInt32Array in and out")
	_check(failures, counter.halve_floats32(PackedFloat32Array([1.0, 5.0, -3.0])) == PackedFloat32Array([0.5, 2.5, -1.5]), "PackedFloat32Array in and out")
	_check(failures, counter.shift_points(PackedVector2Array([Vector2(1, 2), Vector2(-3, 4)])) == PackedVector2Array([Vector2(11, 22), Vector2(7, 24)]), "PackedVector2Array in and out")
	_check(failures, counter.stretch_points(PackedVector3Array([Vector3(1, 2, 3)])) == PackedVector3Array([Vector3(2, 4, 6)]), "PackedVector3Array in and out")
	_check(failures, counter.invert_colors(PackedColorArray([Color(0.25, 0.5, 1.0, 0.75), Color(0, 0, 0, 1)])) == PackedColorArray([Color(0.75, 0.5, 0.0, 0.75), Color(1, 1, 1, 1)]), "PackedColorArray in and out")
	_check(failures, counter.double_ints32(PackedInt32Array()) == PackedInt32Array() and counter.shift_points(PackedVector2Array()) == PackedVector2Array(), "empty numeric packed arrays")
	var untyped_packed: Variant = counter
	_check(failures, untyped_packed.call("shift_points", PackedVector2Array([Vector2(0, 0)])) == PackedVector2Array([Vector2(10, 20)]), "PackedVector2Array through a Variant call")
	_check(failures, untyped_packed.call("invert_colors", PackedColorArray([Color(1, 1, 1, 0.5)])) == PackedColorArray([Color(0, 0, 0, 0.5)]), "PackedColorArray through a Variant call")
	var many_points := PackedVector2Array()
	many_points.resize(50000)
	many_points.fill(Vector2(1, 1))
	_check(failures, counter.shift_points(many_points)[49999] == Vector2(11, 21), "a big PackedVector2Array")
	var nested: Array = [1, [2, [3, "x"]], {"k": [1.5, true, {"deep": PackedInt32Array([7, 8])}]}]
	_check(failures, counter.nest_depth(nested) == 4, "nested Arrays and Dictionaries are read: depth %s" % [counter.nest_depth(nested)])
	_check(failures, counter.echo(nested) == nested, "a nested Array through a Variant argument and result: %s" % [counter.echo(nested)])
	_check(failures, counter.echo(5) == 5 and counter.echo("s") == "s" and counter.echo(2.5) == 2.5 and counter.echo(true) == true, "echo of scalars")
	_check(failures, counter.echo(null) == null, "echo of nil")
	_check(failures, counter.echo(Vector2(1, 2)) == Vector2(1, 2) and counter.echo(Vector3(1, 2, 3)) == Vector3(1, 2, 3), "echo of vectors")
	_check(failures, counter.echo(PackedColorArray([Color(1, 0, 0, 1)])) == PackedColorArray([Color(1, 0, 0, 1)]), "echo of a packed array")
	_check(failures, counter.echo({"a": {"b": [1, 2]}}) == {"a": {"b": [1, 2]}}, "echo of nested Dictionaries")
	_check(failures, counter.echo(RID()) == null, "a type without a kind (RID) comes as nil")
	_check(failures, counter.kind_of(5) != counter.kind_of("x") and counter.kind_of([1]) == counter.kind_of([]), "the kind of a Variant argument is the kind that arrived")
	var cycle: Array = []
	cycle.append(cycle)
	_check(failures, counter.nest_depth(cycle) == 9, "an Array that holds itself is read down to the limit and stops: %s" % [counter.nest_depth(cycle)])
	var untyped_echo: Variant = counter
	_check(failures, untyped_echo.call("echo", [1, [2]]) == [1, [2]], "echo through a Variant call")
	_check(failures, counter.step_cell(Vector2i(3, -4)) == Vector2i(4, -5), "Vector2i in and out")
	_check(failures, counter.step_cell3(Vector3i(1, 2, 3)) == Vector3i(2, 4, 6), "Vector3i in and out")
	_check(failures, counter.sum4(Vector4(1, 2, 3, 4.5)) == 10.5, "Vector4 in")
	_check(failures, counter.reverse4(Vector4i(1, 2, 3, 4)) == Vector4i(4, 3, 2, 1), "Vector4i in and out")
	_check(failures, counter.move_rect(Rect2(1, 2, 3, 4)) == Rect2(11, 12, 6, 8), "Rect2 in and out")
	_check(failures, counter.grow_rect(Rect2i(5, 5, 2, 2)) == Rect2i(4, 4, 4, 4), "Rect2i in and out")
	_check(failures, counter.invert_color(Color(0.25, 0.5, 1.0, 0.75)) == Color(0.75, 0.5, 0.0, 0.75), "Color in and out")
	_check(failures, counter.conjugate(Quaternion(0.1, 0.2, 0.3, 0.9)) == Quaternion(-0.1, -0.2, -0.3, 0.9), "Quaternion in and out")
	_check(failures, counter.flip_plane(Plane(1, 0, 0, 5)) == Plane(-1, 0, 0, -5), "Plane in and out")
	_check(failures, counter.grow_box(AABB(Vector3(1, 2, 3), Vector3(4, 5, 6))) == AABB(Vector3(1, 2, 3), Vector3(8, 10, 12)), "AABB in and out")
	_check(failures, counter.slide(Transform2D(0.0, Vector2(1, 1))) == Transform2D(0.0, Vector2(6, 7)), "Transform2D in and out")
	_check(failures, counter.double_basis(Basis.IDENTITY) == Basis(Vector3(2, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 2)), "Basis in and out")
	_check(failures, counter.lift(Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))) == Transform3D(Basis.IDENTITY, Vector3(1, 3, 3)), "Transform3D in and out")
	_check(failures, counter.double_projection(Projection.IDENTITY) == Projection(Vector4(2, 0, 0, 0), Vector4(0, 2, 0, 0), Vector4(0, 0, 2, 0), Vector4(0, 0, 0, 2)), "Projection in and out")
	_check(failures, counter.shout_name(&"ab") == &"AB" and counter.shout_name(&"") == &"", "StringName in and out")
	_check(failures, counter.shout_path(NodePath("a/b:c")) == NodePath("A/B:C"), "NodePath in and out")
	var untyped_pod: Variant = counter
	_check(failures, untyped_pod.call("move_rect", Rect2(0, 0, 1, 1)) == Rect2(10, 10, 2, 2), "Rect2 through a Variant call")
	_check(failures, untyped_pod.call("lift", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))) == Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), "Transform3D through a Variant call")
	_check(failures, untyped_pod.call("shout_name", &"x") == &"X" and untyped_pod.call("shout_path", NodePath("n")) == NodePath("N"), "names through a Variant call")
	_check(failures, counter.echo([Vector2i(1, 2), Rect2(1, 2, 3, 4), Color(1, 0, 0, 1), Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)), AABB(Vector3(1, 1, 1), Vector3(2, 2, 2))]) == [Vector2i(1, 2), Rect2(1, 2, 3, 4), Color(1, 0, 0, 1), Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)), AABB(Vector3(1, 1, 1), Vector3(2, 2, 2))], "structs inside an Array through a Variant")
	_check(failures, counter.echo({"c": Color(0, 1, 0, 1), "r": Rect2i(1, 2, 3, 4)}) == {"c": Color(0, 1, 0, 1), "r": Rect2i(1, 2, 3, 4)}, "structs inside a Dictionary through a Variant")
	_check(failures, counter.echo(Rect2(1, 2, 3, 4)) == Rect2(1, 2, 3, 4) and counter.echo(Basis.IDENTITY) == Basis.IDENTITY, "echo of structs")
	_check(failures, counter.prefix_sums(PackedInt64Array()) == PackedInt64Array(), "an empty PackedInt64Array")
	var big := PackedInt64Array()
	big.resize(100000)
	big.fill(2)
	_check(failures, counter.prefix_sums(big)[99999] == 200000, "a big PackedInt64Array")
	var holder := Node2D.new()
	var child := Node.new()
	holder.add_child(child)
	_check(failures, counter.child_count(holder) == 1, "an engine call: Node.get_child_count")
	_check(failures, counter.parent_of(child) == holder, "an Object as a result: Node.get_parent")
	_check(failures, counter.parent_of(holder) == null, "a null Object result")
	_check(failures, counter.place(holder, Vector2(3, 4)) and holder.position == Vector2(3, 4), "an engine call with a Vector2: Node2D.set_position")
	_check(failures, counter.rename(child, "Kid") == "Kid" and child.name == "Kid", "generated wrappers: Node.set_name and the StringName result of Node.get_name")
	holder.free()
	var painted := Node2D.new()
	_check(failures, counter.tint(painted, Color(1, 0, 0, 0.5)) and painted.modulate == Color(1, 0, 0, 0.5), "generated wrapper with a Color argument: CanvasItem.set_modulate")
	_check(failures, counter.tint_of(painted) == Color(1, 0, 0, 0.5), "generated wrapper with a Color result: CanvasItem.get_modulate")
	var panel := Control.new()
	panel.position = Vector2(3, 4)
	panel.size = Vector2(50, 60)
	_check(failures, counter.rect_of(panel) == Rect2(3, 4, 50, 60), "generated wrapper with a Rect2 result: Control.get_rect: %s" % [counter.rect_of(panel)])
	var parent_node := Node.new()
	var first_child := Node.new()
	var second_child := Node.new()
	parent_node.add_child(first_child)
	parent_node.add_child(second_child)
	_check(failures, counter.children_of(parent_node) == [first_child, second_child], "generated wrapper with a typed Array result: Node.get_children")
	_check(failures, counter.keep_meta(parent_node, "stash", [1, {"a": Vector2i(1, 2)}]) == [1, {"a": Vector2i(1, 2)}], "generated wrappers with a Variant in and out: Object.set_meta and get_meta")
	_check(failures, parent_node.get_meta("stash") == [1, {"a": Vector2i(1, 2)}], "the engine kept the metadata")
	painted.free()
	panel.free()
	parent_node.free()
	_check(failures, counter.is_even(4) and not counter.is_even(7), "is_even")
	_check(failures, counter.greet("Godot") == "Hello, Godot!", "greet")
	_check(failures, counter.greet("Zoë") == "Hello, Zoë!", "greet with a non ASCII letter")
	_check(failures, counter.reverse(PackedByteArray([1, 2, 3])) == PackedByteArray([3, 2, 1]), "reverse")
	_check(failures, counter.reverse(PackedByteArray()) == PackedByteArray(), "reverse of nothing")
	_check(failures, counter.mix(-42, "text", true) == "text/yes/-42", "mix")
	counter.reset()
	_check(failures, counter.get() == 0, "reset")
	# a second object has a state of its own
	var other := Counter.new()
	_check(failures, other.add(1) == 1 and counter.get() == 0, "objects are independent")
	# typed GDScript calls the native way (ptrcall)
	var typed: Counter = Counter.new()
	var number: int = typed.add(3)
	var text: String = typed.greet("typed")
	_check(failures, number == 3 and text == "Hello, typed!", "typed calls")
	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL ", failures)
		quit(1)


func _check(failures: Array, condition: bool, name: String) -> void:
	if not condition:
		failures.append(name)

func _double(x: int) -> int:
	return x * 2
