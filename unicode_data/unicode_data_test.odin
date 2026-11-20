#+build !js
package unicode_data

import "core:strconv"
import "core:strings"
import "core:testing"

GRAPHEME_TESTS :: #load("testdata/GraphemeBreakTest.txt", string)

// The official test file of Unicode: every line is a sequence of code points with a boundary (÷) or no boundary (×) between them
@(test)
test_the_grapheme_breaks_of_the_official_test_file :: proc(t: ^testing.T) {
    text: string = GRAPHEME_TESTS
    lines: int
    failures: int
    for line in strings.split_lines_iterator(&text) {
        content: string = line
        if hash := strings.index_byte(content, '#'); hash >= 0 { content = content[:hash] }
        content = strings.trim_space(content)
        if content == "" { continue }
        characters: [dynamic]rune
        expected: [dynamic]bool          // is there a boundary before characters[i]
        defer delete(characters)
        defer delete(expected)
        pending: bool
        for token in strings.fields_iterator(&content) {
            switch token {
            case "÷": pending = true
            case "×": pending = false
            case:
                code, ok := strconv.parse_int(token, 16)
                if !ok { continue }
                append(&characters, rune(code))
                append(&expected, pending)
            }
        }
        lines += 1
        state: GraphemeState
        for character, i in characters {
            got: bool = GraphemeBreak(&state, character)
            if got != expected[i] {
                failures += 1
                if failures <= 5 { testing.expectf(t, false, "line %d (%s): boundary before character %d is %v, the file says %v", lines, line[:min(len(line), 70)], i, got, expected[i]) }
                break
            }
        }
    }
    testing.expect(t, lines > 500, "the test file was read")
    testing.expect_value(t, failures, 0)
}

@(test)
test_widths_and_properties_of_known_characters :: proc(t: ^testing.T) {
    testing.expect_value(t, RuneWidth('a'), 1)
    testing.expect_value(t, RuneWidth(' '), 1)
    testing.expect_value(t, RuneWidth('~'), 1)
    testing.expect_value(t, RuneWidth(0x00), 0)                  // controls take no room
    testing.expect_value(t, RuneWidth(0x1b), 0)
    testing.expect_value(t, RuneWidth(0x7f), 0)
    testing.expect_value(t, RuneWidth(0x00e9), 1)                // é
    testing.expect_value(t, RuneWidth(0x00ad), 0)                // the soft hyphen (Cf)
    testing.expect_value(t, RuneWidth(0x0301), 0)                // a combining accent (Mn)
    testing.expect_value(t, RuneWidth(0x20dd), 0)                // an enclosing mark (Me)
    testing.expect_value(t, RuneWidth(0x200b), 0)                // zero width space (Cf)
    testing.expect_value(t, RuneWidth(0x200d), 0)                // the joiner
    testing.expect_value(t, RuneWidth(0xfe0f), 0)                // variation selector 16
    testing.expect_value(t, RuneWidth(0x0e34), 0)                // a Thai vowel above (Mn)
    testing.expect_value(t, RuneWidth(0x1161), 0)                // a Hangul vowel jamo
    testing.expect_value(t, RuneWidth(0x1100), 2)                // a Hangul lead jamo (W)
    testing.expect_value(t, RuneWidth(0xac00), 2)                // a Hangul syllable
    testing.expect_value(t, RuneWidth(0x4e2d), 2)                // a Chinese character
    testing.expect_value(t, RuneWidth(0x3042), 2)                // Hiragana
    testing.expect_value(t, RuneWidth(0xff21), 2)                // a fullwidth Latin letter
    testing.expect_value(t, RuneWidth(0xff71), 1)                // a halfwidth Katakana
    testing.expect_value(t, RuneWidth(0x20000), 2)               // a rare Chinese character
    testing.expect_value(t, RuneWidth(0x1f600), 2)               // an emoji picture
    testing.expect_value(t, RuneWidth(0x231a), 2)                // the watch (emoji presentation)
    testing.expect_value(t, RuneWidth(0x2764), 1)                // the heart: text by default
    testing.expect_value(t, RuneWidth(0x1f1e9), 2)               // half of a flag
    testing.expect_value(t, RuneWidth(0x1f3fd), 2)               // an emoji skin tone alone
    testing.expect_value(t, RuneWidth(0x10ffff), 1)
    testing.expect_value(t, RuneWidth(0x110000), 1)
    testing.expect_value(t, RuneWidth(-1), 1)
    // ambiguous
    testing.expect(t, RuneAmbiguous(0x03b1) && RuneAmbiguous(0x0416) && RuneAmbiguous(0x2500) && RuneAmbiguous(0x00b0) && RuneAmbiguous(0xe000))
    testing.expect(t, !RuneAmbiguous('a') && !RuneAmbiguous(0x4e2d) && !RuneAmbiguous(0x00f6) && !RuneAmbiguous(0x1f600))
    // emoji by a variation selector
    testing.expect(t, RuneEmojiText(0x2764) && RuneEmojiText(0x2600) && RuneEmojiText(0x00a9) && RuneEmojiText(0x2122))
    testing.expect(t, !RuneEmojiText('a') && !RuneEmojiText('1') && !RuneEmojiText(0x1f600) && !RuneEmojiText(0x231a))
    testing.expect_value(t, ClusterWidth(0x2764), 1)
    testing.expect_value(t, ClusterWidth(0x2764, 0xfe0f), 2)
    testing.expect_value(t, ClusterWidth('a', 0xfe0f), 1)
    testing.expect_value(t, ClusterWidth(0x1f600), 2)
    testing.expect_value(t, ClusterWidth(0x1f600, 0xfe0e), 1)
    // classes
    testing.expect_value(t, RuneGraphemeClass('a'), GraphemeClass.OTHER)
    testing.expect_value(t, RuneGraphemeClass('\r'), GraphemeClass.CR)
    testing.expect_value(t, RuneGraphemeClass('\n'), GraphemeClass.LF)
    testing.expect_value(t, RuneGraphemeClass(0x0301), GraphemeClass.EXTEND)
    testing.expect_value(t, RuneGraphemeClass(0x200d), GraphemeClass.ZWJ)
    testing.expect_value(t, RuneGraphemeClass(0x1f1e9), GraphemeClass.REGIONAL_INDICATOR)
    testing.expect_value(t, RuneGraphemeClass(0x1100), GraphemeClass.L)
    testing.expect_value(t, RuneGraphemeClass(0xac00), GraphemeClass.LV)
    testing.expect_value(t, RuneGraphemeClass(0xac01), GraphemeClass.LVT)
    testing.expect(t, RuneExtendedPictographic(0x1f600) && RuneExtendedPictographic(0x2764) && !RuneExtendedPictographic('a'))
    testing.expect_value(t, RuneConjunct(0x094d), Conjunct.LINKER)
    testing.expect_value(t, RuneConjunct(0x0915), Conjunct.CONSONANT)
}

@(test)
test_clusters_of_text_people_write :: proc(t: ^testing.T) {
    clusters :: proc(text: string) -> int {
        state: GraphemeState
        count: int
        for character in text {
            if GraphemeBreak(&state, character) { count += 1 }
        }
        return count
    }
    testing.expect_value(t, clusters(""), 0)
    testing.expect_value(t, clusters("abc"), 3)
    testing.expect_value(t, clusters("é"), 1)                              // a letter and its accent
    testing.expect_value(t, clusters("\r\n"), 1)
    testing.expect_value(t, clusters("\n\n"), 2)
    testing.expect_value(t, clusters("\U0001F468‍\U0001F469‍\U0001F467‍\U0001F466"), 1)   // a family
    testing.expect_value(t, clusters("\U0001F1E9\U0001F1EA"), 1)                 // a flag
    testing.expect_value(t, clusters("\U0001F1E9\U0001F1EA\U0001F1EB\U0001F1F7"), 2)    // two flags
    testing.expect_value(t, clusters("\U0001F1E9\U0001F1EA\U0001F1EB"), 2)       // a flag and half of one
    testing.expect_value(t, clusters("\U0001F44D\U0001F3FD"), 1)                 // a thumb and its skin tone
    testing.expect_value(t, clusters("❤️"), 1)
    testing.expect_value(t, clusters("한"), 1)                   // a Hangul syllable of three jamo
    testing.expect_value(t, clusters("क्ष"), 1)                   // an Indic conjunct (GB9c): ka, virama, ssa
    testing.expect_value(t, clusters("a‍b"), 2)                             // a joiner between letters joins the joiner only
    testing.expect_value(t, clusters("กิ่"), 1)                   // Thai: a letter, a vowel and a tone
}
