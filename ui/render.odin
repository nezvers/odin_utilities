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
