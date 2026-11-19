package font

// The outlines of an OpenType font with PostScript outlines (the CFF table): every glyph is a small program (a Type 2 charstring) that moves a pen with lines and cubic curves and
// calls subroutines. The program is run straight into the curves of the caller (the cubics are cut into quadratics there), on a fixed stack: nothing is allocated.
//
// The interpreter is the one of stb_truetype v1.28 (see sfnt.odin for the credit): the same operators, the same rounding of every point to whole font units.

@(private)
FontCff :: struct {
    table: []u8,                // the whole CFF table: the offsets of the dictionaries count from its start
    charstrings: []u8,          // an index: the program of every glyph
    global_subroutines: []u8,
    local_subroutines: []u8,
    // a CID font has several font dictionaries, each with its own local subroutines, and a table that says which glyph uses which
    font_dicts: []u8,
    font_dict_select: []u8,
}

@(private)
CFF_STACK :: 48                 // the numbers a program may have waiting for an operator
@(private)
CFF_CALL_DEPTH :: 10            // subroutines inside of subroutines

@(private)
cffLoad :: proc "contextless" (table: []u8) -> (cff: FontCff, ok: bool) {
    if len(table) == 0 { return }
    cff.table = table
    _, names_end := cffIndex(table, cffUint(table, 2, 1))
    top_dicts, top_dicts_end := cffIndex(table, names_end)
    top: []u8 = cffIndexItem(top_dicts, 0)
    _, strings_end := cffIndex(table, top_dicts_end)
    cff.global_subroutines, _ = cffIndex(table, strings_end)

    charstrings, _ := cffDictInts(top, 17)
    charstring_type, type_count := cffDictInts(top, 0x100 | 6)
    font_dicts, _ := cffDictInts(top, 0x100 | 36)
    font_dict_select, _ := cffDictInts(top, 0x100 | 37)
    cff.local_subroutines = cffLocalSubroutines(table, top)
    if (type_count > 0 && charstring_type[0] != 2) || charstrings[0] == 0 { return }
    if font_dicts[0] != 0 {
        if font_dict_select[0] == 0 { return }
        cff.font_dicts, _ = cffIndex(table, int(font_dicts[0]))
        cff.font_dict_select = cffSlice(table, int(font_dict_select[0]), len(table) - int(font_dict_select[0]))
    }
    cff.charstrings, _ = cffIndex(table, int(charstrings[0]))
    return cff, true
}

// A number of `size` bytes, the bytes outside of the data count as 0
@(private)
cffUint :: proc "contextless" (data: []u8, offset: int, size: int) -> int {
    value: int
    for i in 0 ..< size {
        value <<= 8
        if offset + i >= 0 && offset + i < len(data) { value |= int(data[offset + i]) }
    }
    return value
}

@(private)
cffReadUint :: proc "contextless" (data: []u8, cursor: ^int, size: int) -> int {
    value: int = cffUint(data, cursor^, size)
    cursor^ = min(cursor^ + size, len(data))
    return value
}

@(private)
cffClamp :: proc "contextless" (data: []u8, offset: int) -> int {
    return len(data) if offset > len(data) || offset < 0 else offset
}

@(private)
cffSlice :: proc "contextless" (data: []u8, offset: int, size: int) -> []u8 {
    if offset < 0 || size < 0 || offset > len(data) || size > len(data) - offset { return nil }
    return data[offset:offset + size]
}

// An index (a count, offsets, then the items) that starts at `offset`, and where it ends
@(private)
cffIndex :: proc "contextless" (data: []u8, offset: int) -> (index: []u8, next: int) {
    start: int = cffClamp(data, offset)
    cursor: int = start
    count: int = cffReadUint(data, &cursor, 2)
    if count != 0 {
        offset_size: int = cffReadUint(data, &cursor, 1)
        if offset_size < 1 || offset_size > 4 { return nil, cursor }
        cursor = cffClamp(data, cursor + offset_size * count)
        last: int = cffReadUint(data, &cursor, offset_size)
        cursor = cffClamp(data, cursor + last - 1)
    }
    return data[start:cursor], cursor
}

@(private)
cffIndexItem :: proc "contextless" (index: []u8, item: int) -> []u8 {
    count: int = cffUint(index, 0, 2)
    offset_size: int = cffUint(index, 2, 1)
    if item < 0 || item >= count || offset_size < 1 || offset_size > 4 { return nil }
    offset: int = 3 + item * offset_size
    start: int = cffUint(index, offset, offset_size)
    end: int = cffUint(index, offset + offset_size, offset_size)
    return cffSlice(index, 2 + (count + 1) * offset_size + start, end - start)
}

// A whole number of a dictionary or a charstring (the length of its encoding depends on the first byte)
@(private)
cffInt :: proc "contextless" (data: []u8, cursor: ^int) -> u32 {
    first: int = cffReadUint(data, cursor, 1)
    if first >= 32 && first <= 246 {
        return u32(first - 139)
    } else if first >= 247 && first <= 250 {
        return u32((first - 247) * 256 + cffReadUint(data, cursor, 1) + 108)
    } else if first >= 251 && first <= 254 {
        return u32(-(first - 251) * 256 - cffReadUint(data, cursor, 1) - 108)
    } else if first == 28 {
        return u32(cffReadUint(data, cursor, 2))
    } else if first == 29 {
        return u32(cffReadUint(data, cursor, 4))
    }
    return 0
}

// The (up to two) whole numbers before the operator `key` in a dictionary; zeros when it has none
@(private)
cffDictInts :: proc "contextless" (dict: []u8, key: int) -> (values: [2]u32, count: int) {
    cursor: int = 0
    for cursor < len(dict) {
        start: int = cursor
        for cffUint(dict, cursor, 1) >= 28 {
            if cffUint(dict, cursor, 1) == 30 {
                // a real number: nibbles until the end mark
                cursor += 1
                for cursor < len(dict) {
                    nibbles: int = cffReadUint(dict, &cursor, 1)
                    if (nibbles & 0xF) == 0xF || (nibbles >> 4) == 0xF { break }
                }
            } else {
                cffInt(dict, &cursor)
            }
        }
        end: int = cursor
        operator: int = cffReadUint(dict, &cursor, 1)
        if operator == 12 { operator = cffReadUint(dict, &cursor, 1) | 0x100 }
        if operator == key {
            operands: []u8 = dict[start:end]
            operand_cursor: int = 0
            for count < len(values) && operand_cursor < len(operands) {
                values[count] = cffInt(operands, &operand_cursor)
                count += 1
            }
            return
        }
    }
    return
}

// The local subroutines that the private dictionary of a font dictionary points to
@(private)
cffLocalSubroutines :: proc "contextless" (table: []u8, font_dict: []u8) -> []u8 {
    private, _ := cffDictInts(font_dict, 18)
    private_size: int = int(private[0])
    private_offset: int = int(private[1])
    if private_size == 0 || private_offset == 0 { return nil }
    offset, _ := cffDictInts(cffSlice(table, private_offset, private_size), 19)
    if offset[0] == 0 { return nil }
    subroutines, _ := cffIndex(table, private_offset + int(offset[0]))
    return subroutines
}

// The local subroutines of a glyph of a CID font: those of the font dictionary the glyph belongs to
@(private)
cffGlyphSubroutines :: proc "contextless" (cff: ^FontCff, glyph: int) -> []u8 {
    select: []u8 = cff.font_dict_select
    selector: int = -1
    switch cffUint(select, 0, 1) {
    case 0:
        selector = cffUint(select, 1 + glyph, 1)
    case 3:
        range_count: int = cffUint(select, 1, 2)
        start: int = cffUint(select, 3, 2)
        for range in 0 ..< range_count {
            value: int = cffUint(select, 5 + range * 3, 1)
            end: int = cffUint(select, 6 + range * 3, 2)
            if glyph >= start && glyph < end {
                selector = value
                break
            }
            start = end
        }
    }
    if selector == -1 { return nil }
    return cffLocalSubroutines(cff.table, cffIndexItem(cff.font_dicts, selector))
}

@(private)
CffPen :: struct {
    sink: ^OutlineSink,
    x: f32,
    y: f32,
    first_x: f32,
    first_y: f32,
}

@(private)
cffClose :: proc "contextless" (pen: ^CffPen) {
    if pen.first_x != pen.x || pen.first_y != pen.y { sinkLine(pen.sink, int(pen.first_x), int(pen.first_y)) }
}

@(private)
cffMove :: proc "contextless" (pen: ^CffPen, dx: f32, dy: f32) {
    cffClose(pen)
    pen.x += dx
    pen.y += dy
    pen.first_x = pen.x
    pen.first_y = pen.y
    sinkMove(pen.sink, int(pen.x), int(pen.y))
}

@(private)
cffLine :: proc "contextless" (pen: ^CffPen, dx: f32, dy: f32) {
    pen.x += dx
    pen.y += dy
    sinkLine(pen.sink, int(pen.x), int(pen.y))
}

@(private)
cffCurve :: proc "contextless" (pen: ^CffPen, dx1: f32, dy1: f32, dx2: f32, dy2: f32, dx3: f32, dy3: f32) {
    cx1: f32 = pen.x + dx1
    cy1: f32 = pen.y + dy1
    cx2: f32 = cx1 + dx2
    cy2: f32 = cy1 + dy2
    pen.x = cx2 + dx3
    pen.y = cy2 + dy3
    sinkCubic(pen.sink, int(pen.x), int(pen.y), int(cx1), int(cy1), int(cx2), int(cy2))
}

// Runs the program of a glyph into the sink. False for a program that is broken or does not end: the sink then holds a part of the glyph, the caller throws it away.
@(private)
cffGlyphOutline :: proc "contextless" (cff: ^FontCff, glyph: int, sink: ^OutlineSink) -> bool {
    pen: CffPen = {sink = sink}
    in_header: bool = true
    mask_bits: int
    call_depth: int
    count: int                                  // the numbers on the stack
    has_subroutines: bool
    stack: [CFF_STACK]f32 = ---
    call_code: [CFF_CALL_DEPTH][]u8 = ---
    call_cursor: [CFF_CALL_DEPTH]int = ---
    subroutines: []u8 = cff.local_subroutines
    f: f32

    code: []u8 = cffIndexItem(cff.charstrings, glyph)
    cursor: int = 0
    for cursor < len(code) {
        i: int = 0
        clear_stack: bool = true
        operator: int = cffReadUint(code, &cursor, 1)
        switch operator {
        case 0x13, 0x14:                        // hintmask, cntrmask: a bit per hint follows
            if in_header { mask_bits += count / 2 }
            in_header = false
            cursor = cffClamp(code, cursor + (mask_bits + 7) / 8)
        case 0x01, 0x03, 0x12, 0x17:            // the hints: only counted, to know how long a mask is
            mask_bits += count / 2
        case 0x15:                              // rmoveto
            in_header = false
            if count < 2 { return false }
            cffMove(&pen, stack[count - 2], stack[count - 1])
        case 0x04:                              // vmoveto
            in_header = false
            if count < 1 { return false }
            cffMove(&pen, 0, stack[count - 1])
        case 0x16:                              // hmoveto
            in_header = false
            if count < 1 { return false }
            cffMove(&pen, stack[count - 1], 0)
        case 0x05:                              // rlineto
            if count < 2 { return false }
            for ; i + 1 < count; i += 2 {
                cffLine(&pen, stack[i], stack[i + 1])
            }
        case 0x07, 0x06:                        // vlineto, hlineto: lines that take turns
            if count < 1 { return false }
            vertical: bool = operator == 0x07
            for {
                if !vertical {
                    if i >= count { break }
                    cffLine(&pen, stack[i], 0)
                    i += 1
                }
                vertical = false
                if i >= count { break }
                cffLine(&pen, 0, stack[i])
                i += 1
            }
        case 0x1F, 0x1E:                        // hvcurveto, vhcurveto: curves that take turns
            if count < 4 { return false }
            horizontal: bool = operator == 0x1F
            for {
                if !horizontal {
                    if i + 3 >= count { break }
                    cffCurve(&pen, 0, stack[i], stack[i + 1], stack[i + 2], stack[i + 3], stack[i + 4] if count - i == 5 else 0)
                    i += 4
                }
                horizontal = false
                if i + 3 >= count { break }
                cffCurve(&pen, stack[i], 0, stack[i + 1], stack[i + 2], stack[i + 4] if count - i == 5 else 0, stack[i + 3])
                i += 4
            }
        case 0x08:                              // rrcurveto
            if count < 6 { return false }
            for ; i + 5 < count; i += 6 {
                cffCurve(&pen, stack[i], stack[i + 1], stack[i + 2], stack[i + 3], stack[i + 4], stack[i + 5])
            }
        case 0x18:                              // rcurveline
            if count < 8 { return false }
            for ; i + 5 < count - 2; i += 6 {
                cffCurve(&pen, stack[i], stack[i + 1], stack[i + 2], stack[i + 3], stack[i + 4], stack[i + 5])
            }
            if i + 1 >= count { return false }
            cffLine(&pen, stack[i], stack[i + 1])
        case 0x19:                              // rlinecurve
            if count < 8 { return false }
            for ; i + 1 < count - 6; i += 2 {
                cffLine(&pen, stack[i], stack[i + 1])
            }
            if i + 5 >= count { return false }
            cffCurve(&pen, stack[i], stack[i + 1], stack[i + 2], stack[i + 3], stack[i + 4], stack[i + 5])
        case 0x1A, 0x1B:                        // vvcurveto, hhcurveto
            if count < 4 { return false }
            f = 0
            if count & 1 != 0 {
                f = stack[i]
                i += 1
            }
            for ; i + 3 < count; i += 4 {
                if operator == 0x1B {
                    cffCurve(&pen, stack[i], f, stack[i + 1], stack[i + 2], stack[i + 3], 0)
                } else {
                    cffCurve(&pen, f, stack[i], stack[i + 1], stack[i + 2], 0, stack[i + 3])
                }
                f = 0
            }
        case 0x0A, 0x1D:                        // callsubr, callgsubr
            if operator == 0x0A && !has_subroutines {
                if len(cff.font_dict_select) != 0 { subroutines = cffGlyphSubroutines(cff, glyph) }
                has_subroutines = true
            }
            if count < 1 || call_depth >= CFF_CALL_DEPTH { return false }
            count -= 1
            index: []u8 = subroutines if operator == 0x0A else cff.global_subroutines
            subroutine_count: int = cffUint(index, 0, 2)
            // the number in the program is moved so that the short encodings reach the most subroutines
            bias: int = 107
            if subroutine_count >= 33900 {
                bias = 32768
            } else if subroutine_count >= 1240 {
                bias = 1131
            }
            subroutine: int = int(stack[count]) + bias
            if subroutine < 0 || subroutine >= subroutine_count { return false }
            call_code[call_depth] = code
            call_cursor[call_depth] = cursor
            call_depth += 1
            code = cffIndexItem(index, subroutine)
            cursor = 0
            if len(code) == 0 { return false }
            clear_stack = false
        case 0x0B:                              // return
            if call_depth <= 0 { return false }
            call_depth -= 1
            code = call_code[call_depth]
            cursor = call_cursor[call_depth]
            clear_stack = false
        case 0x0E:                              // endchar
            cffClose(&pen)
            return true
        case 0x0C:                              // the two byte operators: the flex curves (two curves that are nearly a line)
            dx1, dx2, dx3, dx4, dx5, dx6, dy1, dy2, dy3, dy4, dy5, dy6: f32
            switch cffReadUint(code, &cursor, 1) {
            case 0x22:                          // hflex
                if count < 7 { return false }
                dx1, dx2, dy2, dx3, dx4, dx5, dx6 = stack[0], stack[1], stack[2], stack[3], stack[4], stack[5], stack[6]
                cffCurve(&pen, dx1, 0, dx2, dy2, dx3, 0)
                cffCurve(&pen, dx4, 0, dx5, -dy2, dx6, 0)
            case 0x23:                          // flex
                if count < 13 { return false }
                dx1, dy1, dx2, dy2, dx3, dy3 = stack[0], stack[1], stack[2], stack[3], stack[4], stack[5]
                dx4, dy4, dx5, dy5, dx6, dy6 = stack[6], stack[7], stack[8], stack[9], stack[10], stack[11]
                cffCurve(&pen, dx1, dy1, dx2, dy2, dx3, dy3)
                cffCurve(&pen, dx4, dy4, dx5, dy5, dx6, dy6)
            case 0x24:                          // hflex1
                if count < 9 { return false }
                dx1, dy1, dx2, dy2, dx3 = stack[0], stack[1], stack[2], stack[3], stack[4]
                dx4, dx5, dy5, dx6 = stack[5], stack[6], stack[7], stack[8]
                cffCurve(&pen, dx1, dy1, dx2, dy2, dx3, 0)
                cffCurve(&pen, dx4, 0, dx5, dy5, dx6, -(dy1 + dy2 + dy5))
            case 0x25:                          // flex1: the last number goes along the longer side
                if count < 11 { return false }
                dx1, dy1, dx2, dy2, dx3, dy3 = stack[0], stack[1], stack[2], stack[3], stack[4], stack[5]
                dx4, dy4, dx5, dy5 = stack[6], stack[7], stack[8], stack[9]
                dx6, dy6 = stack[10], stack[10]
                dx: f32 = dx1 + dx2 + dx3 + dx4 + dx5
                dy: f32 = dy1 + dy2 + dy3 + dy4 + dy5
                if abs(dx) > abs(dy) {
                    dy6 = -dy
                } else {
                    dx6 = -dx
                }
                cffCurve(&pen, dx1, dy1, dx2, dy2, dx3, dy3)
                cffCurve(&pen, dx4, dy4, dx5, dy5, dx6, dy6)
            case:
                return false
            }
        case:
            // a number: 16.16 fixed point after 255, else a whole number
            if operator != 255 && operator != 28 && operator < 32 { return false }
            if operator == 255 {
                f = f32(i32(u32(cffReadUint(code, &cursor, 4)))) / 0x10000
            } else {
                cursor -= 1
                f = f32(i16(cffInt(code, &cursor)))
            }
            if count >= CFF_STACK { return false }
            stack[count] = f
            count += 1
            clear_stack = false
        }
        if clear_stack { count = 0 }
    }
    return false
}
