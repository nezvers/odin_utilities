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
