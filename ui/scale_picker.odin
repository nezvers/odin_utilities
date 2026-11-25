package ui

// The key and the scale of a piece: a dropdown for the root note, a dropdown for the scale, and a strip of the twelve notes that shows which belong to the scale (a click on a note adds it or takes it
// out, the scale becomes "Custom"). The result is what `PianoRollView` takes: `scale_root` (0 is C) and `scale_mask` (bit 0 is the root, bit n the note n semitones above it; 0 shows no scale).
//
//     ui.UiScalePicker(&ctx, "Key", &roll_view.scale_root, &roll_view.scale_mask)
//
// A program that wants only the maths uses `ScaleContains`, `ScaleName`, `ScaleNoteName` and the table `SCALES`.
//
// Limits: twelve tone scales only (no quarter tones, no scales that do not repeat at the octave), note names with sharps (C#, not Db), the root note cannot be taken out of its scale, a mask that is not
//     in the table is called "Custom" (no name search among modes), no keyboard picture, no chord detection.

ScaleDef :: struct {
    name: string,
    mask: u16,              // bit 0 is the root
}

SCALE_CHROMATIC :: u16(0b111111111111)

// The scales of the picker (the first, "Off", shows no scale). Masks are the semitones above the root.
SCALES :: [?]ScaleDef{
    {"Off", 0},
    {"Major", 0b101010110101},
    {"Natural minor", 0b010110101101},
    {"Harmonic minor", 0b100110101101},
    {"Melodic minor", 0b101010101101},
    {"Dorian", 0b011010101101},
    {"Phrygian", 0b010110101011},
    {"Lydian", 0b101010101011},
    {"Mixolydian", 0b011010110101},
    {"Locrian", 0b010101101011},
    {"Major pentatonic", 0b001010010101},
    {"Minor pentatonic", 0b010010101001},
    {"Blues", 0b010011101001},
    {"Whole tone", 0b010101010101},
    {"Diminished", 0b101101101101},
    {"Chromatic", SCALE_CHROMATIC},
}

SCALE_COUNT :: len(SCALES)
SCALE_CUSTOM :: SCALE_COUNT              // the index of "Custom" in the dropdown

@(private)
scaleOptions :: proc() -> [SCALE_COUNT + 1]string {
    options: [SCALE_COUNT + 1]string
    table := SCALES
    for scale, i in table { options[i] = scale.name }
    options[SCALE_CUSTOM] = "Custom"
    return options
}

NOTE_NAMES :: [12]string{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

// The name of a pitch class (any pitch: it is taken modulo 12)
ScaleNoteName :: proc(pitch: int) -> string {
    names := NOTE_NAMES
    return names[(pitch % 12 + 12) % 12]
}

// The index in `SCALES` of a mask, `SCALE_CUSTOM` when it is not there
ScaleIndex :: proc(mask: u16) -> int {
    table := SCALES
    for scale, i in table {
        if scale.mask == mask { return i }
    }
    return SCALE_CUSTOM
}

ScaleName :: proc(mask: u16) -> string {
    return scaleOptions()[ScaleIndex(mask)]
}

// Is this pitch in the scale of a root and a mask (a mask of 0: everything is)
ScaleContains :: proc(root: int, mask: u16, pitch: int) -> bool {
    if mask == 0 { return true }
    degree: int = ((pitch - root) % 12 + 12) % 12
    return mask & (1 << uint(degree)) != 0
}

// `changed` in the frame the key or the scale changed. `root` is a pitch class 0..11, `mask` the notes above it. Ids of the parts under the picker's own: "##root", "##scale", and a note chip is "<note> ##n<degree>" (a space, so that the sharp does not start the "##": "D# ##n1").
UiScalePicker :: proc(ctx: ^Context, name: string, root: ^int, mask: ^u16, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    root^ = (root^ % 12 + 12) % 12
    ElementOpen(ctx, {id = UiId(ctx, name), layout = {size = {size.width if size.width != {} else Fit(), Fit()}, direction = .TOP_TO_BOTTOM, gap = ctx.style.metrics.gap}})
    defer ElementClose(ctx)
    if ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = ctx.style.metrics.gap, align = {y = .CENTER}}}) {
        names := NOTE_NAMES
        picked_root: int = root^
        if UiDropdown(ctx, "##root", names[:], &picked_root, {Fixed(ctx.style.metrics.control_width * 0.5), {}}, disabled) {
            root^ = picked_root
            changed = true
        }
        options := scaleOptions()
        count: int = SCALE_COUNT + 1 if ScaleIndex(mask^) == SCALE_CUSTOM else SCALE_COUNT
        picked: int = ScaleIndex(mask^)
        if UiDropdown(ctx, "##scale", options[:count], &picked, {Grow(), {}}, disabled) && picked != SCALE_CUSTOM {
            table := SCALES
            mask^ = table[picked].mask
            changed = true
        }
    }
    ElementClose(ctx)
    // the twelve notes of the key: lit when they are in the scale, the root first
    if ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}}) {
        for degree in 0 ..< 12 {
            pitch: int = (root^ + degree) % 12
            in_scale: bool = mask^ == 0 || mask^ & (1 << uint(degree)) != 0
            if UiChip(ctx, UiFormat(ctx, "%s ##n%d", ScaleNoteName(pitch), degree), in_scale, disabled = disabled || degree == 0) {
                if mask^ == 0 { mask^ = SCALE_CHROMATIC }
                mask^ ~= 1 << uint(degree)
                if mask^ == 1 { mask^ = 0 }         // only the root left: nothing is a scale
                changed = true
            }
        }
    }
    ElementClose(ctx)
    return
}
