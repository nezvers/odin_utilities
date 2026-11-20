package ui_default

import ui ".."

// An icon of the ui: the Lucide picture through the painter (the icons the library names itself, and every one made with LucideIcon). A painter without icons draws the
// file and folder pictures with rectangles on a grid of 16 x 16, so a tree still has them.
DrawIcon :: proc(ctx: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^Painter = painterOf(ctx)
    color: ui.Color = info.color if info.color.a > 0 else painter.theme.text_dim
    icon: ui.Icon = cast(ui.Icon)clamp(int(info.actual), 0, 0xffff)
    if painter.draw_icon != nil {
        side: f32 = min(info.rect.z, info.rect.w)
        IconAt(painter, IconToLucide(icon), ui.RectCenter(info.rect), side, color)
        return
    }
    soft: ui.Color = ui.ColorLerp(color, painter.theme.track, 0.55)
    unit: f32 = min(info.rect.z, info.rect.w) / 16
    origin: ui.Vec2 = {info.rect.x + (info.rect.z - unit * 16) * 0.5, info.rect.y + (info.rect.w - unit * 16) * 0.5}
    box :: proc(painter: ^Painter, origin: ui.Vec2, unit: f32, x: f32, y: f32, w: f32, h: f32, color: ui.Color) {
        painter.fill_rect(painter, {origin.x + x * unit, origin.y + y * unit, w * unit, h * unit}, color)
    }
    #partial switch icon {
    case .FOLDER:
        box(painter, origin, unit, 1, 3, 6, 3, color)
        box(painter, origin, unit, 1, 5, 14, 9, color)
        box(painter, origin, unit, 2, 7, 12, 1, soft)
    case .FOLDER_OPEN:
        box(painter, origin, unit, 1, 3, 6, 3, color)
        box(painter, origin, unit, 1, 5, 12, 2, color)
        box(painter, origin, unit, 3, 7, 12, 7, soft)
        box(painter, origin, unit, 2, 8, 12, 6, color)
    case .FILE:
        box(painter, origin, unit, 3, 1, 8, 14, color)
        box(painter, origin, unit, 11, 3, 2, 12, color)
        box(painter, origin, unit, 4, 2, 6, 12, soft)
        box(painter, origin, unit, 11, 1, 2, 2, soft)
    case .TEXT:
        box(painter, origin, unit, 3, 1, 10, 14, color)
        box(painter, origin, unit, 4, 2, 8, 12, soft)
        for line in 0 ..< 4 { box(painter, origin, unit, 5, 4 + f32(line) * 2.5, 6, 1, color) }
    case .IMAGE:
        box(painter, origin, unit, 1, 3, 14, 10, color)
        box(painter, origin, unit, 2, 4, 12, 8, soft)
        box(painter, origin, unit, 3, 9, 4, 3, color)
        box(painter, origin, unit, 6, 7, 4, 5, color)
        box(painter, origin, unit, 9, 9, 4, 3, color)
        box(painter, origin, unit, 10, 5, 2, 2, color)
    case .AUDIO:
        box(painter, origin, unit, 9, 2, 2, 9, color)
        box(painter, origin, unit, 5, 10, 6, 4, color)
        box(painter, origin, unit, 11, 2, 3, 3, color)
    case .CLOSE:
        center: ui.Vec2 = ui.RectCenter(info.rect)
        Line(painter, center + {-4, -4} * unit, center + {4, 4} * unit, 1.5 * unit, color)
        Line(painter, center + {-4, 4} * unit, center + {4, -4} * unit, 1.5 * unit, color)
    case .CHEVRON_UP, .CHEVRON_DOWN, .CHEVRON_LEFT, .CHEVRON_RIGHT:
        ArrowShape(painter, ui.RectCenter(info.rect), 8 * unit, int(icon) - int(ui.Icon.CHEVRON_UP), color)
    }
}
