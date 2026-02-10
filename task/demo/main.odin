package demo

import "core:log"

import task ".."
import "core:os"
import "core:os/os2"

download_dir :: "download/"
dependencies_dir :: "dependencies/"
raylib_dir :: "raylib/"

download_raylib_lib :: proc()->(ok:bool){
	return task.download_file(
		"https://github.com/raysan5/raylib/releases/download/5.5/raylib-5.5_linux_amd64.tar.gz",
		download_dir + "raylib-5.5_linux_amd64.tar.gz",
	)
}

extract_raylib_lib :: proc()->(ok:bool){
	return task.extract_tar_archive(download_dir + "raylib-5.5_linux_amd64.tar.gz", download_dir + raylib_dir, "1")
}

clone_raylib_repo :: proc()->(ok:bool){
	if os.exists(raylib_dir){
		return true
	}
	return task.git_clone("https://github.com/raysan5/raylib.git", "5.5", false, true, "1")
}

main :: proc(){
	logger := log.create_console_logger()
	context.logger = logger

	working_dir, err: = os2.get_working_directory(context.allocator)
	defer delete(working_dir)
	// Return user to original directory in case project change it
	defer os2.change_directory(working_dir)
	if err != nil {
		return
	}

	executable_directory:string
	executable_directory, err = os2.get_executable_directory(context.allocator)
	defer delete(executable_directory)
	if err != nil {
		return
	}
	os2.change_directory(executable_directory)

	// DOWNLOAD RAYLIB BINARIES
	if !os.exists(download_dir){
		err = os2.make_directory(download_dir)
		assert(err == nil, "Couldn't make directory - " + download_dir)
	}
	if !os.exists(download_dir + raylib_dir){
		err = os2.make_directory(download_dir + raylib_dir)
		assert(err == nil, "Couldn't make directory - " + download_dir + raylib_dir)
	}

	ok:bool
	if ok = download_raylib_lib(); ok {
		ok = extract_raylib_lib()
		if !ok {
			return
		}
	}
	
	// CLONE RAYLIB REPOSITORY
	if !os.exists(dependencies_dir){
		err = os2.make_directory(dependencies_dir)
		assert(err == nil, "Couldn't make directory - " + dependencies_dir)
	}
	os2.change_directory(dependencies_dir)

	if ok = clone_raylib_repo(); ok {
	}
	os2.change_directory(executable_directory)
}