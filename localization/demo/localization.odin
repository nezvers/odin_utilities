#+private file
package demo

import rl "vendor:raylib"
Rectangle :: rl.Rectangle

import "core:encoding/csv"
import "core:fmt"
import "core:strings"
// import "core:os"

@(private="package")
state_localization : State = {
    init,
    finit,
    update,
    draw,
}

csv_localization: []byte = #load("../../assets/data/localization.csv")
LANG_MAP :: map[cstring]cstring
localization_map: map[cstring]LANG_MAP
language_list: [dynamic]cstring

init :: proc() {
    language_list = make([dynamic]cstring)
    localization_map = make(map[cstring]LANG_MAP)
    iterate_csv_from_string(csv_localization[:])
}

finit :: proc() {
    for lang_key, lang_map in localization_map {
        _ = lang_key
        for k, v in lang_map {
            _ = k
            delete(v)
        }
        delete(lang_map)
    }
    delete(localization_map)
    delete(language_list)
}

update :: proc() {}

draw :: proc() {
    ROW_HEIGHT :: 25
    button_rect: Rectangle = {10, 10, 100, 20}
    for lang_key in language_list {
        if rl.GuiButton(button_rect, lang_key) {
    
        }
        button_rect.y += ROW_HEIGHT
    }
}

// Requires keeping the entire CSV file in memory at once
iterate_csv_from_string :: proc(csv_data: []byte) {
    reader: csv.Reader
	reader.trim_leading_space  = true
	reader.reuse_record        = true // Without it you have to delete(record)
	reader.reuse_record_buffer = true // Without it you have to each of the fields within it

    csv.reader_init_with_string(&reader, string(csv_data))

	for record, row, err in csv.iterator_next(&reader) {
		if err != nil { continue /* Do something with error */ }
		for value, column in record {
            if row == 0 {
                if column > 0 {
                    cstr: cstring = strings.clone_to_cstring(value)
                    localization_map[cstr] = make(LANG_MAP)
                    append(&language_list, cstr)
                }
            } else {

            }
			fmt.printfln("Record %v, field %v: %q", row, column, value)
		}
	}
}