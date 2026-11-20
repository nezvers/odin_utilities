package unicode_data

// What a text program needs to know about a code point, from the Unicode Character Database (tables.odin, made by tool/gen): how many cells it takes on a terminal or in a grid, whether
// its width is ambiguous, whether a variation selector turns it into an emoji, and where the boundaries of a grapheme cluster (one thing a person sees as one character) are.
//
//     RuneWidth('a')                  1        RuneWidth('中')    2        RuneWidth('́')   0 (goes with the letter before it)
//     RuneAmbiguous('α')         true     (Greek, Cyrillic, box drawing ...: wide in an East Asian locale)
//     RuneEmojiText('❤')         true     (a heart: narrow until a variation selector 16 follows)
//
//     state: GraphemeState
//     for character in text { if GraphemeBreak(&state, character) { /* a new cluster starts here */ } }
//
// A lookup is two array reads (a table of blocks of 256 code points; equal blocks are stored once, 74 KB in all) and costs what a branch does. The width rules, the one set that
// everything in odin_utilities uses (the cell screen of the ui, the text of the font library): 0 for the general categories Mn, Me, Cf and Cc and for the Hangul vowels and finals that
// join a syllable, 2 for East Asian Width W and F and for the regional indicators (half of a flag), 1 for the rest. The cluster rules are UAX #29 of Unicode 18, including the emoji
// sequences (GB11), the flags (GB12, GB13) and the conjuncts of the Indic scripts (GB9c, as Unicode 18 states it). The official test file `testdata/GraphemeBreakTest.txt` is run by the tests.
//
// Limits: the width of a cluster is the width of its first code point (a variation selector 16 on a text-default emoji makes it 2: `ClusterWidth`); no locale (ambiguous characters
//     are narrow unless the caller says), no emoji sequence validation (any pictograph can follow a joiner, as the standard's rule says), code points above U+10FFFF and surrogates
//     are width 1 and class Other; Unicode data of the version in UNICODE_VERSION (a new version is a run of the generator).

Props :: u16

// the bits of a property word (tool/gen writes them)
WIDTH_MASK :: Props(0x3)
AMBIGUOUS :: Props(1 << 2)
EMOJI_TEXT :: Props(1 << 3)
CLASS_SHIFT :: 4
CLASS_MASK :: Props(0xF)
EXT_PICT :: Props(1 << 8)
INCB_SHIFT :: 9

// The Grapheme_Cluster_Break value of a code point
GraphemeClass :: enum u8 {
    OTHER,
    CR,
    LF,
    CONTROL,
    EXTEND,
    ZWJ,
    REGIONAL_INDICATOR,
    PREPEND,
    SPACING_MARK,
    L,
    V,
    T,
    LV,
    LVT,
}

// Indic_Conjunct_Break
Conjunct :: enum u8 {
    NONE,
    CONSONANT,
    LINKER,
    EXTEND,
}

// The property word of a code point
PropsOf :: #force_inline proc "contextless" (character: rune) -> Props {
    code: u32 = u32(character)
    if code > 0x10FFFF { return 1 }
    return STAGE2[int(STAGE1[code >> 8]) * 256 + int(code & 0xFF)]
}

// How many cells: 0, 1 or 2
RuneWidth :: #force_inline proc "contextless" (character: rune) -> int {
    return int(PropsOf(character) & WIDTH_MASK)
}

// East Asian Width A
RuneAmbiguous :: #force_inline proc "contextless" (character: rune) -> bool {
    return PropsOf(character) & AMBIGUOUS != 0
}

// A narrow character that a variation selector 16 turns into an emoji picture (a heart, a sun, a check mark)
RuneEmojiText :: #force_inline proc "contextless" (character: rune) -> bool {
    return PropsOf(character) & EMOJI_TEXT != 0
}

RuneGraphemeClass :: #force_inline proc "contextless" (character: rune) -> GraphemeClass {
    return GraphemeClass((PropsOf(character) >> CLASS_SHIFT) & CLASS_MASK)
}

RuneExtendedPictographic :: #force_inline proc "contextless" (character: rune) -> bool {
    return PropsOf(character) & EXT_PICT != 0
}

RuneConjunct :: #force_inline proc "contextless" (character: rune) -> Conjunct {
    return Conjunct((PropsOf(character) >> INCB_SHIFT) & 0x3)
}

// The width of a cluster that starts with `first` and has `variation` as its second code point (0 for none): the width of the first code point, and 2 for a text-default emoji
// followed by a variation selector 16 (U+FE0F), 1 for any wide one followed by a variation selector 15 (U+FE0E, the text form)
ClusterWidth :: proc "contextless" (first: rune, variation: rune = 0) -> int {
    width: int = RuneWidth(first)
    if variation == 0xFE0F && width == 1 && RuneEmojiText(first) { return 2 }
    if variation == 0xFE0E && width == 2 && RuneExtendedPictographic(first) { return 1 }
    return width
}

// ---- grapheme clusters -----------------------------------------------------------------------------------------------------------------------------------------------

// What the break rules remember of the text before: the class of the last code point, and the three states of the rules that look back (an emoji and its joiner, the regional indicators
// of a flag, an Indic consonant and its linker). The zero value is the start of a text.
GraphemeState :: struct {
    previous: GraphemeClass,
    started: bool,
    emoji: u8,                  // 0 none, 1 after a pictograph and its extenders, 2 after those and a joiner (GB11)
    indicators: u8,             // the regional indicators in a row, counted up to 2
    conjunct: u8,               // 0 none, 2 after an Indic linker and the extenders and linkers that follow it (GB9c)
}

// Is there a cluster boundary before `character`, given everything the state has seen; takes the character into the state. The first character of a text starts a cluster (true).
GraphemeBreak :: proc "contextless" (state: ^GraphemeState, character: rune) -> bool {
    props: Props = PropsOf(character)
    class: GraphemeClass = GraphemeClass((props >> CLASS_SHIFT) & CLASS_MASK)
    pictograph: bool = props & EXT_PICT != 0
    conjunct: Conjunct = Conjunct((props >> INCB_SHIFT) & 0x3)
    previous: GraphemeClass = state.previous
    boundary: bool = true
    switch {
    case !state.started:
        boundary = true
    case previous == .CR && class == .LF:                       // GB3
        boundary = false
    case previous == .CR || previous == .LF || previous == .CONTROL:    // GB4
        boundary = true
    case class == .CR || class == .LF || class == .CONTROL:     // GB5
        boundary = true
    case previous == .L && (class == .L || class == .V || class == .LV || class == .LVT):   // GB6
        boundary = false
    case (previous == .LV || previous == .V) && (class == .V || class == .T):               // GB7
        boundary = false
    case (previous == .LVT || previous == .T) && class == .T:                               // GB8
        boundary = false
    case class == .EXTEND || class == .ZWJ:                    // GB9 (and GB9c: an extender or a linker keeps the conjunct going, handled below)
        boundary = false
    case class == .SPACING_MARK:                                // GB9a
        boundary = false
    case previous == .PREPEND:                                  // GB9b
        boundary = false
    case state.conjunct == 2 && conjunct == .CONSONANT:         // GB9c
        boundary = false
    case state.emoji == 2 && pictograph:                        // GB11
        boundary = false
    case previous == .REGIONAL_INDICATOR && class == .REGIONAL_INDICATOR && state.indicators == 1:   // GB12, GB13
        boundary = false
    case:
        boundary = true
    }
    // the states
    if boundary || !state.started {
        state.emoji, state.indicators, state.conjunct = 0, 0, 0
    }
    // GB11: ExtPict Extend* ZWJ x ExtPict
    switch {
    case pictograph:
        state.emoji = 1
    case class == .EXTEND && state.emoji == 1:
        // stays
    case class == .ZWJ && state.emoji == 1:
        state.emoji = 2
    case:
        state.emoji = 0
    }
    // GB12 and GB13: a flag is a pair of regional indicators: the count of them in a row since the last boundary (a third one starts a new pair)
    if class == .REGIONAL_INDICATOR {
        state.indicators = 1 if boundary else state.indicators + 1
    } else {
        state.indicators = 0
    }
    // GB9c as the test file of Unicode 18 has it: a consonant joins what follows a linker (and the extenders and linkers after it), whatever came before the linker
    switch {
    case conjunct == .LINKER:
        state.conjunct = 2
    case conjunct == .EXTEND:
        // stays: after a linker the state goes on, else there is none
    case:
        state.conjunct = 0
    }
    state.previous = class
    state.started = true
    return boundary
}
