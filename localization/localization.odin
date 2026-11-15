package localization


import "core:encoding/csv"
import "core:testing"

LocalizationData :: struct {
    array: []string,            // 1d array of strings from CSV: slices of `chars`
    chars: []u8,                // the text of every cell, packed one after another (a linear allocation: one block for all strings)
    columns: u32,               // store count of CSV columns
    rows: u32,                  // store count of CSV rows
    lang_map: map[string] u32,  // column index for languages
    key_map: map[string] u32,   // row index for translated text
}

// Cleanup: two blocks and two maps, whatever the number of strings
DeleteLocalizationData :: proc(data: ^LocalizationData, allocator := context.allocator, loc := #caller_location) {
    context.allocator = allocator
    delete(data.array)
    delete(data.chars)
    delete(data.key_map)
    delete(data.lang_map)
    data ^= {}
}

// Parse. All the strings of the table share one lifetime, so they are packed into one block: the text of the cells together is never
// longer than the CSV itself (quotes and separators are dropped), which makes the size of the block known before the first cell is read.
MakeLocalizationData :: proc(csv_bytes: []byte, allocator := context.allocator, loc := #caller_location)->(data: LocalizationData) {
    context.allocator = allocator
    data.key_map = make(map[string]u32)
    data.lang_map = make(map[string]u32)

    reader: csv.Reader
    defer csv.reader_destroy(&reader)

	reader.trim_leading_space  = true
	reader.fields_per_record  = -1   // a short row is allowed, its missing cells stay empty
	reader.reuse_record        = true // Without it you have to delete(record)
	reader.reuse_record_buffer = true // Without it you have to each of the fields within it

    // first pass: the size of the table, so the array has its exact size and never grows (growing would move the strings)
    csv.reader_init_with_string(&reader, string(csv_bytes))
    for record, row, err in csv.iterator_next(&reader) {
        if err != nil { continue }
        if cast(u32)row <= data.rows { data.rows = cast(u32)row + 1 }
        for _, column in record {
            if cast(u32)column <= data.columns { data.columns = cast(u32)column + 1 }
        }
    }
    csv.reader_destroy(&reader)
    reader = {}
	reader.trim_leading_space  = true
	reader.fields_per_record  = -1   // a short row is allowed, its missing cells stay empty
	reader.reuse_record        = true
	reader.reuse_record_buffer = true

    // a cell is at row * columns + column, a short row leaves empty cells
    data.array = make([]string, int(data.rows * data.columns), allocator, loc)
    data.chars = make([]u8, len(csv_bytes), allocator, loc)
    used: int = 0       // the linear allocator: the length of what is packed so far

    // second pass: the cells go into the block one after another
    csv.reader_init_with_string(&reader, string(csv_bytes))
	for record, row, err in csv.iterator_next(&reader) {
		if err != nil { continue /* Do something with error */ }
		for value, column in record {
            copy(data.chars[used:], value)
            data.array[row * int(data.columns) + column] = string(data.chars[used:used + len(value)])
            used += len(value)
		}
	}

    // collect column index for languages
    for i:u32 = 1; i < data.columns; i += 1 {
        lang_string: string = data.array[i]
        data.lang_map[lang_string] = i
    }

    // collect row index for translations
    for i:u32 = 1; i < data.rows; i += 1 {
        index: u32 = i * data.columns
        key_string: string = data.array[index]
        data.key_map[key_string] = i
    }
    return
}

// Fetch slice of langage keys
GetLanguages :: proc(data: ^LocalizationData)->(buffer: []string, ok: bool) {
    if len(data.array) < 2 { return }
    ok = true
    buffer = data.array[1:data.columns]
    return 
}

// Get language index to use it for indexing translation
GetLanguageId :: proc(data: ^LocalizationData, key: string)->(id: u32, ok: bool) {
    id, ok = data.lang_map[key]
    return
}

// Get text index to use it for indexing translation
GetTextId :: proc(data: ^LocalizationData, key: string)->(id: u32, ok: bool) {
    id, ok = data.key_map[key]
    return
}

// Get translated text using text key and language key from GetLanguageId & GetTextId
GetTranslationById :: proc(data: ^LocalizationData, text_id: u32, lang_id: u32)->(translation:string, ok: bool) {
    if !(lang_id > 0 && lang_id < data.columns) { return }
    if !(text_id > 0 && text_id < data.rows) { return }

    index:u32 = data.columns * text_id + lang_id
    translation = data.array[index]
    ok = true
    return
}

// Get translated text using text key and language key
// Recommended to cache their ID with GetLanguageId & GetTextId to get directly with GetTranslationById
GetTranslation :: proc(data: ^LocalizationData, text: string, language: string)->(translation:string, ok: bool) {
    lang_id, lang_ok: = GetLanguageId(data, language)
    if !lang_ok { return }
    text_id, text_ok: = GetTextId(data, text)
    if !text_ok { return }

    translation, ok = GetTranslationById(data, text_id, lang_id)
    return
}

// --- Tests ---

@(private="file")
TEST_CSV :: "key,en,lv\nhello,Hello,Sveiki\nbye,Bye,Atā\n"

@(test)
test_localization_parses_the_table :: proc(t: ^testing.T) {
    data: LocalizationData = MakeLocalizationData(transmute([]byte)string(TEST_CSV))
    defer DeleteLocalizationData(&data)

    testing.expect_value(t, data.columns, u32(3))
    testing.expect_value(t, data.rows, u32(3))
    testing.expect_value(t, len(data.array), 9)

    languages, ok := GetLanguages(&data)
    testing.expect(t, ok)
    testing.expect_value(t, len(languages), 2)
    testing.expect_value(t, languages[0], "en")
    testing.expect_value(t, languages[1], "lv")
}

@(test)
test_localization_lookup :: proc(t: ^testing.T) {
    data: LocalizationData = MakeLocalizationData(transmute([]byte)string(TEST_CSV))
    defer DeleteLocalizationData(&data)

    text, found := GetTranslation(&data, "hello", "lv")
    testing.expect(t, found)
    testing.expect_value(t, text, "Sveiki")
    text, found = GetTranslation(&data, "bye", "en")
    testing.expect(t, found)
    testing.expect_value(t, text, "Bye")

    _, missing_text := GetTranslation(&data, "nope", "en")
    testing.expect(t, !missing_text)
    _, missing_language := GetTranslation(&data, "hello", "de")
    testing.expect(t, !missing_language)

    // the cached route
    language, _ := GetLanguageId(&data, "lv")
    key, _ := GetTextId(&data, "bye")
    cached, cached_ok := GetTranslationById(&data, key, language)
    testing.expect(t, cached_ok)
    testing.expect_value(t, cached, "Atā")

    _, bad_row := GetTranslationById(&data, 99, language)
    testing.expect(t, !bad_row)
    _, header_row := GetTranslationById(&data, 0, language)                                // row 0 is the header, not a text
    testing.expect(t, !header_row)
    _, key_column := GetTranslationById(&data, key, 0)                                     // column 0 holds the keys
    testing.expect(t, !key_column)
}

@(test)
test_localization_empty_input :: proc(t: ^testing.T) {
    data: LocalizationData = MakeLocalizationData(nil)
    defer DeleteLocalizationData(&data)
    _, ok := GetLanguages(&data)
    testing.expect(t, !ok)
    testing.expect_value(t, data.rows, u32(0))
}

@(test)
test_localization_short_rows_and_quotes :: proc(t: ^testing.T) {
    csv_text: string = "key,en,lv\nhello,\"Hello, you\"\nbye,Bye,Atā\n"       // a short row and a quoted comma
    data: LocalizationData = MakeLocalizationData(transmute([]byte)csv_text)
    defer DeleteLocalizationData(&data)
    text, ok := GetTranslation(&data, "hello", "en")
    testing.expect(t, ok)
    testing.expect_value(t, text, "Hello, you")
    text, ok = GetTranslation(&data, "hello", "lv")
    testing.expect(t, ok)
    testing.expect_value(t, text, "")                                            // the missing cell is empty, not out of range
    text, _ = GetTranslation(&data, "bye", "lv")
    testing.expect_value(t, text, "Atā")
}
