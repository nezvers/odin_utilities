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
	data_as_string := "Odin is great!\n"
    data_as_bytes := transmute([]byte)(data_as_string) // 'transmute' casts our string to a byte array
	data_as_string2 := "Sky is blue.\n"
    data_as_bytes2 := transmute([]byte)(data_as_string2) // 'transmute' casts our string to a byte array

	file: = save.create("output.txt")
	defer save.close(file)
	if file != nil {
		save.write_append(file, data_as_bytes[:])
		save.write_append(file, data_as_bytes2[:])
	}
	// save.write_file("output.txt")
	save.read_file("output.txt")
}

finit :: proc() {}
update :: proc() {}
draw :: proc() {}
