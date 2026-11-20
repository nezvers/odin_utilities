package ui

// Colors inside of a text area: `ui.UiTextArea(..., highlight = ui.HighlightCode, highlight_user = &language)` draws the words of a line in the colors of what they
// are. A highlighter cuts a row into spans, each with a tag for the style ("syntax keyword" ...; the default style has a color for each), and the area declares a
// text per span of the rows in view. Nothing is allocated; the text, the caret and the selection are the ones of the area.
//
// What goes over several lines (a block comment, a raw string) is carried from row to row in a `state`: a number the highlighter gets at the start of a row and
// leaves at its end (0 at the start of the text). The area runs the highlighter over all rows once when the text changed and keeps the state of every row with its
// rows, so a frame only reads the rows in view.
//
// `HighlightCode` is a highlighter for languages that look like C or Odin, by a table of words. A string in quotes ends at the end of its row.
//
// Limits: HighlightCode reads languages like C or Odin by a table of words: no grammar, no language detection, a string in quotes ends with its row, numbers are a guess (digits and letters)
//     at most AREA_SPANS (96) spans in a row; the state of a row is one number, so it carries block comments and raw strings and nothing more; all rows are read again when the text changes
//
// Baldr's code editor (examples/07_code) was the reason to have it; the code is written for this library.

// A piece of a row and the tag it is drawn with ("": plain)
TextSpan :: struct {
    length: int,                // bytes
    tag: string,
}

// Cuts the row `text[row_start:row_end]` into spans, in order, written into `spans`; returns how many. What the spans do not cover (the rest of the row, or all of
// it when the room is too small) is plain. `state`: what the rows before left open, to be left as it is at the end of this row (never nil when the area calls;
// it has to be right also when the spans do not fit).
TextHighlight :: proc(text: string, row_start: int, row_end: int, spans: []TextSpan, user: rawptr, state: ^u32) -> int

// The spans a text area has room for in one row
AREA_SPANS :: 96

SYNTAX_KEYWORD :: "syntax keyword"
SYNTAX_TYPE :: "syntax type"
SYNTAX_STRING :: "syntax string"
SYNTAX_NUMBER :: "syntax number"
SYNTAX_COMMENT :: "syntax comment"

// What HighlightCode knows of a language (`highlight_user` is a pointer to one, it has to live as long as the area is declared with it)
HighlightLanguage :: struct {
    keywords: []string,
    types: []string,
    line_comment: string,       // what starts a comment that goes to the end of the line ("//", "#"); "": none
    block_open: string,         // a comment over several lines ("/*" and "*/"); "": none
    block_close: string,
    block_nests: bool,          // a block comment inside of a block comment has its own end (Odin), or the first end closes it (C)
    raw_quote: u8,              // the quote of a string that goes over several lines and has no escapes (the backtick of Odin and Go); 0: none
}

// The words of Odin
ODIN_KEYWORDS: [35]string = {
    "package", "import", "proc", "struct", "enum", "union", "bit_set", "map", "distinct", "using", "defer", "if", "else", "when", "for", "in", "not_in", "switch",
    "case", "break", "continue", "fallthrough", "return", "foreign", "dynamic", "cast", "transmute", "auto_cast", "context", "nil", "true", "false", "or_else",
    "or_return", "where",
}
ODIN_TYPES: [22]string = {
    "int", "uint", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "uintptr", "f32", "f64", "bool", "string", "cstring", "rune", "rawptr", "any", "typeid",
    "byte", "b32",
}
HIGHLIGHT_ODIN: HighlightLanguage = {keywords = ODIN_KEYWORDS[:], types = ODIN_TYPES[:], line_comment = "//", block_open = "/*", block_close = "*/", block_nests = true, raw_quote = '`'}

// The state of HighlightCode: how deep it is inside of block comments, or that it is inside of a raw string
@(private)
HIGHLIGHT_RAW_STRING :: 0x8000_0000

@(private)
highlightIsWord :: proc "contextless" (character: u8) -> bool {
    return character == '_' || (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character >= 0x80
}

@(private)
highlightAt :: proc "contextless" (text: string, i: int, row_end: int, mark: string) -> bool {
    return mark != "" && i + len(mark) <= row_end && text[i:i + len(mark)] == mark
}

// From `i` inside of a block comment `depth` deep: where the comment ends on this row (or the end of the row) and how deep it is there
@(private)
highlightBlock :: proc "contextless" (language: ^HighlightLanguage, text: string, from: int, row_end: int, depth_in: u32) -> (i: int, depth: u32) {
    i, depth = from, depth_in
    for i < row_end && depth > 0 {
        if highlightAt(text, i, row_end, language.block_close) {
            depth -= 1
            i += len(language.block_close)
        } else if language.block_nests && highlightAt(text, i, row_end, language.block_open) {
            depth += 1
            i += len(language.block_open)
        } else {
            i += 1
        }
    }
    return
}

// A TextHighlight for code: comments to the end of the line and over several lines, strings in double quotes, single quotes and raw quotes (a backslash keeps the
// quote after it, not in a raw string), numbers, the keywords and the types of the language. `user`: a ^HighlightLanguage (nil: Odin).
HighlightCode :: proc(text: string, row_start: int, row_end: int, spans: []TextSpan, user: rawptr, state: ^u32 = nil) -> int {
    language: ^HighlightLanguage = cast(^HighlightLanguage)user if user != nil else &HIGHLIGHT_ODIN
    open: u32 = state^ if state != nil else 0
    defer if state != nil { state^ = open }
    count: int
    full: bool
    // pieces that follow each other with the same tag are one span; when the room is used up the row is still read to its end, for the state
    put :: proc(spans: []TextSpan, count: ^int, full: ^bool, length: int, tag: string) {
        if length <= 0 || full^ { return }
        if count^ > 0 && spans[count^ - 1].tag == tag {
            spans[count^ - 1].length += length
            return
        }
        if count^ >= len(spans) {
            full^ = true
            return
        }
        spans[count^] = {length, tag}
        count^ += 1
    }
    i: int = row_start
    // what the rows before left open
    if open == HIGHLIGHT_RAW_STRING {
        for i < row_end && text[i] != language.raw_quote { i += 1 }
        if i < row_end {
            i += 1
            open = 0
        }
        put(spans, &count, &full, i - row_start, SYNTAX_STRING)
    } else if open > 0 {
        i, open = highlightBlock(language, text, i, row_end, open)
        put(spans, &count, &full, i - row_start, SYNTAX_COMMENT)
    }
    for i < row_end {
        character: u8 = text[i]
        start: int = i
        tag: string
        switch {
        case highlightAt(text, i, row_end, language.line_comment):
            i = row_end
            tag = SYNTAX_COMMENT
        case highlightAt(text, i, row_end, language.block_open):
            i, open = highlightBlock(language, text, i + len(language.block_open), row_end, 1)
            tag = SYNTAX_COMMENT
        case character == '"' || character == '\'' || (character == language.raw_quote && character != 0):
            raw: bool = character == language.raw_quote
            i += 1
            for i < row_end && text[i] != character {
                if text[i] == '\\' && !raw && i + 1 < row_end { i += 1 }
                i += 1
            }
            if i < row_end {
                i += 1
            } else if raw {
                open = HIGHLIGHT_RAW_STRING
            }
            tag = SYNTAX_STRING
        case character >= '0' && character <= '9':
            // digits, a base (0x), a point, an exponent, underscores
            for i < row_end && (highlightIsWord(text[i]) || (text[i] == '.' && i + 1 < row_end && text[i + 1] >= '0' && text[i + 1] <= '9')) { i += 1 }
            tag = SYNTAX_NUMBER
        case highlightIsWord(character):
            for i < row_end && highlightIsWord(text[i]) { i += 1 }
            word: string = text[start:i]
            for keyword in language.keywords {
                if keyword == word { tag = SYNTAX_KEYWORD }
            }
            if tag == "" {
                for type in language.types {
                    if type == word { tag = SYNTAX_TYPE }
                }
            }
        case:
            i += 1
        }
        put(spans, &count, &full, i - start, tag)
    }
    return count
}
