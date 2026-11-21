extends SceneTree

# Run by the test of the template: `godot --headless --path godot_project --script test.gd`

func _init() -> void:
	var failures := []
	var counter := Counter.new()
	_check(failures, counter.add(5) == 5, "add 5")
	_check(failures, counter.add(7) == 12, "add 7")
	_check(failures, counter.get() == 12, "get")
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
