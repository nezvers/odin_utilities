package ui

// Colors inside of a text area: `ui.UiTextArea(..., highlight = ui.HighlightCode, highlight_user = &language)` draws the words of a line in the colors of what they
// are. The area asks for every row it shows, every frame: a highlighter cuts the row into spans, each with a tag for the style ("syntax keyword" ...; the default
// style has a color for each), and the area declares a text per span. Nothing is kept and nothing is allocated; the text, the caret and the selection are the ones
// of the area.
//
// `HighlightCode` is a highlighter for languages that look like C or Odin, by a table of words. It reads a row on its own: a comment or a string that goes over
// several lines is only colored on the line it starts in, and with `wrap` on a string that is broken over two rows loses its color on the second.
//
// Baldr's code editor (examples/07_code) was the reason to have it; the code is written for this library.

// A piece of a row and the tag it is drawn with ("": plain)
TextSpan :: struct {
    length: int,                // bytes
    tag: string,
}

// Cuts the row `text[row_start:row_end]` into spans, in order, written into `spans`; returns how many. What the spans do not cover (the rest of the row, or all of
// it when the room is too small) is plain. The whole text is given so that a highlighter may look at what is before the row.
TextHighlight :: proc(text: string, row_start: int, row_end: int, spans: []TextSpan, user: rawptr) -> int

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
HIGHLIGHT_ODIN: HighlightLanguage = {keywords = ODIN_KEYWORDS[:], types = ODIN_TYPES[:], line_comment = "//"}

@(private)
highlightIsWord :: proc "contextless" (character: u8) -> bool {
    return character == '_' || (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character >= 0x80
}

// A TextHighlight for code: comments to the end of the line, strings in double quotes, single quotes and backticks (a backslash keeps the quote after it), numbers,
// the keywords and the types of the language. `user`: a ^HighlightLanguage (nil: Odin).
HighlightCode :: proc(text: string, row_start: int, row_end: int, spans: []TextSpan, user: rawptr) -> int {
    language: ^HighlightLanguage = cast(^HighlightLanguage)user if user != nil else &HIGHLIGHT_ODIN
    count: int
    // pieces that follow each other with the same tag are one span
    put :: proc(spans: []TextSpan, count: ^int, length: int, tag: string) -> bool {
        if length <= 0 { return true }
        if count^ > 0 && spans[count^ - 1].tag == tag {
            spans[count^ - 1].length += length
            return true
        }
        if count^ >= len(spans) { return false }
        spans[count^] = {length, tag}
        count^ += 1
        return true
    }
    i: int = row_start
    for i < row_end {
        character: u8 = text[i]
        start: int = i
        tag: string
        comment: string = language.line_comment
        switch {
        case comment != "" && i + len(comment) <= row_end && text[i:i + len(comment)] == comment:
            i = row_end
            tag = SYNTAX_COMMENT
        case character == '"' || character == '\'' || character == '`':
            i += 1
            for i < row_end && text[i] != character {
                if text[i] == '\\' && character != '`' && i + 1 < row_end { i += 1 }
                i += 1
            }
            if i < row_end { i += 1 }
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
        if !put(spans, &count, i - start, tag) { break }
    }
    return count
}
