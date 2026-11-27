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
	counter.reset()
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
	_check(failures, counter.echo(Rect2(1, 2, 3, 4)) == null, "a type without a kind comes as nil")
	_check(failures, counter.kind_of(5) != counter.kind_of("x") and counter.kind_of([1]) == counter.kind_of([]), "the kind of a Variant argument is the kind that arrived")
	var cycle: Array = []
	cycle.append(cycle)
	_check(failures, counter.nest_depth(cycle) == 9, "an Array that holds itself is read down to the limit and stops: %s" % [counter.nest_depth(cycle)])
	var untyped_echo: Variant = counter
	_check(failures, untyped_echo.call("echo", [1, [2]]) == [1, [2]], "echo through a Variant call")
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
