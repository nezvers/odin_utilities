#+private file
package demo

import rl "vendor:raylib"
Rectangle :: rl.Rectangle

import "core:encoding/csv"
import "core:fmt"
import "core:os"

@(private="package")
state_localization : State = {
    init,
    finit,
    update,
    draw,
}

init :: proc() {
    iterate_csv_from_string("../assets/data/localization.csv")
}

finit :: proc() {
}

update :: proc() {}

draw :: proc() {
    ROW_HEIGHT :: 25
    button_rect: Rectangle = {10, 10, 100, 20}
    if rl.GuiButton(button_rect, "En") {

    }
}

// Requires keeping the entire CSV file in memory at once
iterate_csv_from_string :: proc(filename: string) {
    reader: csv.Reader
	reader.trim_leading_space  = true
	reader.reuse_record        = true // Without it you have to delete(record)
	reader.reuse_record_buffer = true // Without it you have to each of the fields within it

	csv_data, csv_err := os.read_entire_file(filename, context.allocator)
	defer delete(csv_data)

	if csv_err == nil {
		csv.reader_init_with_string(&reader, string(csv_data))
	} else {
		fmt.eprintfln("Unable to open file: %v. Error: %v", filename, csv_err)
		return
	}

	for record, row, err in csv.iterator_next(&reader) {
		if err != nil { continue /* Do something with error */ }
		for value, column in record {
			fmt.printfln("Record %v, field %v: %q", row, column, value)
		}
	}
}