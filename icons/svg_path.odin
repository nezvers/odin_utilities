package icons

// The path data of SVG (the `d` attribute) as a list of moves, lines and curves in absolute coordinates. Every command of the path grammar is read: relative ones, the short forms
// (H, V, S, T), numbers written without a separator ("1-.5.5") and elliptical arcs, which come out as cubic curves. Nothing is allocated: the segments go into the slice of the caller.

import "core:math"

Vec2 :: [2]f32

SegmentKind :: enum u8 {
    MOVE,               // p[0]: where the next subpath starts
    LINE,               // p[0]: the end
    QUADRATIC,          // p[0]: the control point, p[1]: the end
    CUBIC,              // p[0], p[1]: the control points, p[2]: the end
    CLOSE,              // back to the start of the subpath
}

PathSegment :: struct {
    kind: SegmentKind,
    p: [3]Vec2,
}

@(private)
PathReader :: struct {
    text: string,
    at: int,
}

@(private)
pathSkip :: proc(reader: ^PathReader) {
    for reader.at < len(reader.text) {
        switch reader.text[reader.at] {
        case ' ', '\t', '\r', '\n', ',':
            reader.at += 1
        case:
            return
        }
    }
}

// The next number of the path. A number ends where the next one starts: at a second point or at a sign that is not the one of an exponent.
@(private)
pathNumber :: proc(reader: ^PathReader) -> (value: f32, ok: bool) {
    pathSkip(reader)
    text: string = reader.text
    at: int = reader.at
    negative: bool
    if at < len(text) && (text[at] == '-' || text[at] == '+') {
        negative = text[at] == '-'
        at += 1
    }
    number: f64
    digits: int
    for at < len(text) && text[at] >= '0' && text[at] <= '9' {
        number = number * 10 + f64(text[at] - '0')
        at += 1
        digits += 1
    }
    if at < len(text) && text[at] == '.' {
        at += 1
        place: f64 = 0.1
        for at < len(text) && text[at] >= '0' && text[at] <= '9' {
            number += f64(text[at] - '0') * place
            place *= 0.1
            at += 1
            digits += 1
        }
    }
    if digits == 0 { return 0, false }
    if at + 1 < len(text) && (text[at] == 'e' || text[at] == 'E') {
        mark: int = at + 1
        exponent_negative: bool
        if text[mark] == '-' || text[mark] == '+' {
            exponent_negative = text[mark] == '-'
            mark += 1
        }
        exponent: int
        exponent_digits: int
        for mark < len(text) && text[mark] >= '0' && text[mark] <= '9' {
            exponent = exponent * 10 + int(text[mark] - '0')
            mark += 1
            exponent_digits += 1
        }
        if exponent_digits > 0 {
            number *= math.pow(10, f64(-exponent if exponent_negative else exponent))
            at = mark
        }
    }
    reader.at = at
    return f32(-number if negative else number), true
}

// A flag of an arc is one character, 0 or 1, and may stand right before the next number ("0 01-5")
@(private)
pathFlag :: proc(reader: ^PathReader) -> (value: bool, ok: bool) {
    pathSkip(reader)
    if reader.at >= len(reader.text) { return false, false }
    character: u8 = reader.text[reader.at]
    if character != '0' && character != '1' { return false, false }
    reader.at += 1
    return character == '1', true
}

@(private)
pathAdd :: proc(out: []PathSegment, count: ^int, segment: PathSegment) -> bool {
    if count^ >= len(out) { return false }
    out[count^] = segment
    count^ += 1
    return true
}

// An arc of an ellipse from `from` to `to` as cubic curves (a piece for every quarter turn at most), by the rules of the SVG implementation notes: radii that are too
// small for the two points are scaled up, a radius of zero is a line.
@(private)
pathArc :: proc(out: []PathSegment, count: ^int, from: Vec2, radius: Vec2, rotation_degrees: f32, large: bool, sweep: bool, to: Vec2) -> bool {
    if from == to { return true }
    rx: f64 = f64(abs(radius.x))
    ry: f64 = f64(abs(radius.y))
    if rx < 1e-9 || ry < 1e-9 { return pathAdd(out, count, {kind = .LINE, p = {to, {}, {}}}) }
    angle: f64 = f64(rotation_degrees) * math.PI / 180
    cos_angle: f64 = math.cos(angle)
    sin_angle: f64 = math.sin(angle)
    // the middle of the two points is the origin, the axes of the ellipse are the axes
    half_x: f64 = f64(from.x - to.x) / 2
    half_y: f64 = f64(from.y - to.y) / 2
    x1: f64 = cos_angle * half_x + sin_angle * half_y
    y1: f64 = -sin_angle * half_x + cos_angle * half_y
    lambda: f64 = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
        grow: f64 = math.sqrt(lambda)
        rx *= grow
        ry *= grow
    }
    numerator: f64 = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    denominator: f64 = rx * rx * y1 * y1 + ry * ry * x1 * x1
    factor: f64 = math.sqrt(max(0, numerator / denominator)) if denominator > 0 else 0
    if large == sweep { factor = -factor }
    center_x1: f64 = factor * rx * y1 / ry
    center_y1: f64 = -factor * ry * x1 / rx
    center_x: f64 = cos_angle * center_x1 - sin_angle * center_y1 + f64(from.x + to.x) / 2
    center_y: f64 = sin_angle * center_x1 + cos_angle * center_y1 + f64(from.y + to.y) / 2
    start: f64 = math.atan2((y1 - center_y1) / ry, (x1 - center_x1) / rx)
    end: f64 = math.atan2((-y1 - center_y1) / ry, (-x1 - center_x1) / rx)
    turn: f64 = end - start
    if sweep && turn < 0 { turn += 2 * math.PI }
    if !sweep && turn > 0 { turn -= 2 * math.PI }

    pieces: int = max(1, int(math.ceil(abs(turn) / (math.PI / 2) - 1e-9)))
    step: f64 = turn / f64(pieces)
    // the length of the handles of a cubic that follows a circle over `step`
    handle: f64 = 4.0 / 3.0 * math.tan(step / 4)
    point :: proc(center_x, center_y, rx, ry, cos_angle, sin_angle, x, y: f64) -> Vec2 {
        return {f32(center_x + cos_angle * rx * x - sin_angle * ry * y), f32(center_y + sin_angle * rx * x + cos_angle * ry * y)}
    }
    for piece in 0 ..< pieces {
        a0: f64 = start + step * f64(piece)
        a1: f64 = a0 + step
        cos0, sin0: f64 = math.cos(a0), math.sin(a0)
        cos1, sin1: f64 = math.cos(a1), math.sin(a1)
        c1: Vec2 = point(center_x, center_y, rx, ry, cos_angle, sin_angle, cos0 - handle * sin0, sin0 + handle * cos0)
        c2: Vec2 = point(center_x, center_y, rx, ry, cos_angle, sin_angle, cos1 + handle * sin1, sin1 - handle * cos1)
        // the last piece ends exactly where the path says, not where the rounding of the angles put it
        last: Vec2 = to if piece == pieces - 1 else point(center_x, center_y, rx, ry, cos_angle, sin_angle, cos1, sin1)
        if !pathAdd(out, count, {kind = .CUBIC, p = {c1, c2, last}}) { return false }
    }
    return true
}

// Reads path data into `out`. `ok` is false when the data is not a path or `out` is too small (what was read up to there is in `count`).
SvgPathParse :: proc(data: string, out: []PathSegment) -> (count: int, ok: bool) {
    reader: PathReader = {text = data}
    command: u8
    pen: Vec2
    start: Vec2                 // of the subpath, where Z goes back to
    last_control: Vec2          // of the curve before, for S and T
    last_kind: u8               // the command before, without its case
    for {
        pathSkip(&reader)
        if reader.at >= len(data) { break }
        character: u8 = data[reader.at]
        if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') {
            command = character
            reader.at += 1
        } else if command == 0 {
            return count, false
        } else if command == 'M' {
            command = 'L'                       // more pairs after a move are lines
        } else if command == 'm' {
            command = 'l'
        } else if command == 'Z' || command == 'z' {
            return count, false
        }
        relative: bool = command >= 'a'
        base: Vec2 = pen if relative else Vec2{}
        kind: u8 = command if !relative else command - 32
        switch kind {
        case 'M':
            x := pathNumber(&reader) or_return
            y := pathNumber(&reader) or_return
            pen = base + {x, y}
            start = pen
            pathAdd(out, &count, {kind = .MOVE, p = {pen, {}, {}}}) or_return
        case 'L':
            x := pathNumber(&reader) or_return
            y := pathNumber(&reader) or_return
            pen = base + {x, y}
            pathAdd(out, &count, {kind = .LINE, p = {pen, {}, {}}}) or_return
        case 'H':
            x := pathNumber(&reader) or_return
            pen.x = base.x + x
            pathAdd(out, &count, {kind = .LINE, p = {pen, {}, {}}}) or_return
        case 'V':
            y := pathNumber(&reader) or_return
            pen.y = base.y + y
            pathAdd(out, &count, {kind = .LINE, p = {pen, {}, {}}}) or_return
        case 'C', 'S':
            c1: Vec2 = pen
            if kind == 'C' {
                x := pathNumber(&reader) or_return
                y := pathNumber(&reader) or_return
                c1 = base + {x, y}
            } else if last_kind == 'C' || last_kind == 'S' {
                c1 = pen * 2 - last_control     // the mirror of the control point before
            }
            x2 := pathNumber(&reader) or_return
            y2 := pathNumber(&reader) or_return
            x := pathNumber(&reader) or_return
            y := pathNumber(&reader) or_return
            c2: Vec2 = base + {x2, y2}
            pen = base + {x, y}
            last_control = c2
            pathAdd(out, &count, {kind = .CUBIC, p = {c1, c2, pen}}) or_return
        case 'Q', 'T':
            control: Vec2 = pen
            if kind == 'Q' {
                x := pathNumber(&reader) or_return
                y := pathNumber(&reader) or_return
                control = base + {x, y}
            } else if last_kind == 'Q' || last_kind == 'T' {
                control = pen * 2 - last_control
            }
            x := pathNumber(&reader) or_return
            y := pathNumber(&reader) or_return
            pen = base + {x, y}
            last_control = control
            pathAdd(out, &count, {kind = .QUADRATIC, p = {control, pen, {}}}) or_return
        case 'A':
            rx := pathNumber(&reader) or_return
            ry := pathNumber(&reader) or_return
            rotation := pathNumber(&reader) or_return
            large := pathFlag(&reader) or_return
            sweep := pathFlag(&reader) or_return
            x := pathNumber(&reader) or_return
            y := pathNumber(&reader) or_return
            target: Vec2 = base + {x, y}
            pathArc(out, &count, pen, {rx, ry}, rotation, large, sweep, target) or_return
            pen = target
        case 'Z':
            pen = start
            pathAdd(out, &count, {kind = .CLOSE}) or_return
        case:
            return count, false
        }
        last_kind = kind
    }
    return count, true
}
