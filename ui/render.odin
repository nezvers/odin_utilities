package ui

// Drawing: the commands of the last UiEnd go through the style procs, in order. Nothing here opens a render pass, a batch or a texture:
// call UiRender at the point of the frame where the ui belongs (after the game, before the cursor...) and what the style procs draw lands
// in whatever is open there, so the ui shares the batch of the frame.

// Calls the style for everything the last frame declared. A kind without a proc in the style is skipped.
UiRender :: proc(ctx: ^Context) {
    UiRenderRange(ctx, 0, ctx.command_count)
}

// A part of the commands by index (see UiCommands), for a frame that wants to draw something of its own in the middle of the ui
UiRenderRange :: proc(ctx: ^Context, from: int, to: int) {
    style: ^Style = ctx.style
    assert(style != nil, "UiRender before UiBegin")
    // clips nest (a scrolling list inside of a scrolling window): the style is told the area that is left, so it needs no stack of its own
    clips: [UI_MAX_DEPTH * 2]Rect
    clip_count: int = 0
    zoom_origin: Vec2
    zoom_factor: f32 = 1
    zoom_pushed: bool
    for i in from ..< min(to, ctx.command_count) {
        command: ^Command = &ctx.commands[i]
        switch command.kind {
        case .DRAW:
            if command.info.kind == .CUSTOM {
                if command.info.custom != nil {
                    command.info.custom(ctx, &command.info)
                }
            } else if style.procs[command.info.kind] != nil {
                style.procs[command.info.kind](ctx, &command.info)
            }
        case .CLIP_BEGIN:
            area: Rect = command.info.rect
            if clip_count > 0 { area = RectIntersect(clips[clip_count - 1], area) }
            if clip_count < len(clips) {
                clips[clip_count] = area
                clip_count += 1
            }
            if style.clip != nil { style.clip(ctx, area, true) }
        case .ZOOM_BEGIN:
            zoom_origin, zoom_factor = {command.info.rect.x, command.info.rect.y}, command.info.rect.z
            if style.zoom != nil { style.zoom(ctx, zoom_origin, zoom_factor, true) }
            // the clip that was in force is in screen space: inside of the zoom it is the same area in logical units
            zoom_pushed = false
            if clip_count > 0 && clip_count < len(clips) {
                outer: Rect = clips[clip_count - 1]
                inner: Rect = {zoom_origin.x + (outer.x - zoom_origin.x) / zoom_factor, zoom_origin.y + (outer.y - zoom_origin.y) / zoom_factor, outer.z / zoom_factor, outer.w / zoom_factor}
                clips[clip_count] = inner
                clip_count += 1
                zoom_pushed = true
                if style.clip != nil { style.clip(ctx, inner, true) }
            }
        case .ZOOM_END:
            if zoom_pushed && clip_count > 0 { clip_count -= 1 }
            if style.zoom != nil { style.zoom(ctx, zoom_origin, zoom_factor, false) }
            if zoom_pushed && style.clip != nil {
                if clip_count > 0 {
                    style.clip(ctx, clips[clip_count - 1], true)
                } else {
                    style.clip(ctx, {}, false)
                }
            }
            zoom_pushed = false
        case .CLIP_END:
            if clip_count > 0 { clip_count -= 1 }
            if style.clip != nil {
                if clip_count > 0 {
                    style.clip(ctx, clips[clip_count - 1], true)
                } else {
                    style.clip(ctx, {}, false)
                }
            }
        }
    }
}
