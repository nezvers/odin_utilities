package main

import game "game"
import "core:os"

main :: proc() {
	// To be sure resources/ assets are always relative directory,
	// set working directory where executable is.

	working_dir, err: = os.get_working_directory(context.allocator)
	defer delete(working_dir)
	// Return user to original directory in case project change it
	defer os.change_directory(working_dir)
	if err != nil {
		return
	}
	executable_directory:string
	executable_directory, err = os.get_executable_directory(context.allocator)
	defer delete(executable_directory)
	if err != nil {
		return
	}
	os.change_directory(executable_directory)

	// MAIN LOOP
	main_init()
	game.init()

	for game.step() {
		game.update_desktop()
	}

	game.shutdown()
    main_shutdown()
}

main_init :: proc() {
}

main_shutdown :: proc() {
}