#+private file
package demo

import save ".."

@(private="package")
state_save_basic:State = {
	init,
	finit,
	update,
	draw,
}

init :: proc() {
	save.write_file("output.txt")
	save.read_file("output.txt")
}

finit :: proc() {}
update :: proc() {}
draw :: proc() {}
