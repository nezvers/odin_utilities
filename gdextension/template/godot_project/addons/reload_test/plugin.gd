@tool
extends EditorPlugin

# Hot reload of the extension. Godot reloads an extension only inside the editor, so template_test starts `godot --headless --editor -- <new library> <loaded library>` and this plugin does the
# test: an object made before the reload keeps working after another build of the library replaced the first one, and the engine puts its properties back. Without the two arguments it does
# nothing (the plugin is enabled for every editor session of this project).

func _enter_tree() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 2:
		# the editor finishes starting first
		_run.call_deferred(arguments[0], arguments[1])

func _check(failures: Array, ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)

func _run(new_library: String, loaded_library: String) -> void:
	var failures := []
	var counter = ClassDB.instantiate("Counter")
	counter.total = 7
	_check(failures, counter.version() == 1, "the first build answers: %s" % [counter.version()])
	var kept = ClassDB.instantiate("Counter")
	kept.add(5)

	# another build of the library takes the place of the loaded one (Godot works on a copy of the loaded file, so the original can be written)
	var copied := DirAccess.copy_absolute(new_library, loaded_library)
	_check(failures, copied == OK, "the new library is copied over the old one: %s" % [copied])
	var status := GDExtensionManager.reload_extension("res://template.gdextension")
	_check(failures, status == GDExtensionManager.LOAD_STATUS_OK, "the extension reloads: status %s" % [status])

	_check(failures, counter.version() == 2, "the object that was made before the reload answers with the new build: %s" % [counter.version()])
	_check(failures, counter.total == 7 and counter.get() == 7, "the property total was put back: %s" % [counter.total])
	_check(failures, kept.total == 5, "a second object too: %s" % [kept.total])
	counter.add(3)
	_check(failures, counter.total == 10, "the object works after the reload: %s" % [counter.total])
	var fresh = ClassDB.instantiate("Counter")
	_check(failures, fresh.version() == 2 and fresh.total == 0, "an object made after the reload is a new one")
	if failures.is_empty():
		print("PASS")
	else:
		print("FAIL ", failures)
	get_tree().quit()
