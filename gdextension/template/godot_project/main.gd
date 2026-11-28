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
	# a Tween that Odin makes: the square slides to the right (the engine classes of the generated wrappers)
	var mover := Node2D.new()
	var square := ColorRect.new()
	square.size = Vector2(24, 24)
	mover.add_child(square)
	add_child(mover)
	print("slide -> ", counter.slide_node(mover, Vector2(300, 200), 0.2))
	if DisplayServer.get_name() == "headless":
		await get_tree().create_timer(0.6).timeout
		print("moved to ", mover.position)
		get_tree().quit()
