extends Node

# The testing ground: open this project in Godot (`godot --path godot_project`, or the task "Open In Godot") and press play.
# Change extension.odin, rebuild (task "Build Extension") and run again: the output shows what the extension does.

func _ready() -> void:
	var counter := Counter.new()
	print("add 5 -> ", counter.add(5))
	print("add 7 -> ", counter.add(7))
	print("get -> ", counter.get())
	print("is_even(4) -> ", counter.is_even(4))
	print("greet -> ", counter.greet("Godot"))
	print("reverse -> ", counter.reverse(PackedByteArray([1, 2, 3])))
	print("mix -> ", counter.mix(-42, "text", true))
	counter.reset()
	print("reset, get -> ", counter.get())
	if DisplayServer.get_name() == "headless":
		get_tree().quit()
