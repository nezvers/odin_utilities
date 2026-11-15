package sprite

// Sprite animation as plain data. A Sheet is a row of a constant table: where the frames are on the texture and which frames make
// each clip. An Animator is what changes while playing and refers to the table by number: sheet, clip, frame, time.
// A SheetSprite is an Animator plus the transform. No pointers anywhere in what an instance holds, so it can be copied, put in
// prefab data, overridden by a field patch, saved in a level file and survives a hot reload, where a pointer into the data of the
// old code does not. The older Sprite and AnimationSet (pointers to Frames) stay as they are for code that does not need that.
//
//     character: Sheet = {frame_size = {16, 16}, frames = positions[:], clips = {{0, 2}, {2, 6}}}      // idle: frames 0-1, walk: 2-7
//     sheets: []Sheet = {character}
//     sprite.animator = {sheet = 0, clip = 1, frame_rate = 12}       // then each frame: SheetSpriteUpdate(sheets, &sprite, dt)
//
// This package builds for js_wasm32 (a web game uses it), the tests are in sheet_test.odin.

SheetId :: distinct u16

// Frames of a clip: Sheet.frames[first : first + count]
Clip :: struct {
    first: u16,
    count: u16,
}

Sheet :: struct {
    frame_size: vec2,       // size of one frame on the texture
    frames: []vec2,         // position of each frame on the texture
    clips: []Clip,
}

Animator :: struct {
    sheet: SheetId,         // index in the table of sheets you pass to the procs
    clip: u16,
    image: u16,             // frame inside of the clip
    frame_rate: f32,        // frames per second
    time: f32,              // 0 - 1, how far to the next frame
}

SheetSprite :: struct {
    animator: Animator,
    position: vec2,
    origin: vec2,           // pivot point
    offset: vec2,
    scale: vec2,
    rotation: f32,
}

// The frames of the current clip. Empty when the sheet or the clip does not exist, or the clip points past the frames:
// bad data gives nothing to draw, not a crash
ClipFrames :: proc(sheets: []Sheet, animator: Animator) -> []vec2 {
    if int(animator.sheet) >= len(sheets) { return nil }
    sheet: ^Sheet = &sheets[animator.sheet]
    if int(animator.clip) >= len(sheet.clips) { return nil }
    clip: Clip = sheet.clips[animator.clip]
    if int(clip.first) + int(clip.count) > len(sheet.frames) { return nil }
    return sheet.frames[clip.first:int(clip.first) + int(clip.count)]
}

// Start another clip from its first frame
AnimatorChange :: proc(animator: ^Animator, clip: u16) {
    animator.clip = clip
    animator.image = 0
    animator.time = 0
}

// Advance and loop. Returns true when it went past the last frame and started over
AnimatorUpdate :: proc(sheets: []Sheet, animator: ^Animator, delta_time: f32) -> (wrapped: bool) {
    animator.time += delta_time * animator.frame_rate
    if animator.time < 1 { return }

    count: int = len(ClipFrames(sheets, animator^))
    increment: u32 = cast(u32)animator.time
    animator.time -= cast(f32)increment
    if count == 0 { return }
    next: u32 = u32(animator.image) + increment
    wrapped = next >= u32(count)
    animator.image = u16(next % u32(count))
    return
}

// Advance once, stay on the last frame. Returns true when the last frame was passed (an effect that is over)
AnimatorUpdateOnce :: proc(sheets: []Sheet, animator: ^Animator, delta_time: f32) -> (finished: bool) {
    animator.time += delta_time * animator.frame_rate
    if animator.time < 1 { return }

    count: int = len(ClipFrames(sheets, animator^))
    increment: u32 = cast(u32)animator.time
    animator.time -= cast(f32)increment
    if count == 0 { return true }
    next: u32 = u32(animator.image) + increment
    if next < u32(count) {
        animator.image = u16(next)
        return
    }
    animator.image = u16(count - 1)
    return true
}

// Where the current frame is on the texture: x, y, width, height. Empty when there is nothing to show
AnimatorFrame :: proc(sheets: []Sheet, animator: Animator) -> rectf {
    frames: []vec2 = ClipFrames(sheets, animator)
    if len(frames) == 0 { return {} }
    position: vec2 = frames[min(int(animator.image), len(frames) - 1)]
    size: vec2 = sheets[animator.sheet].frame_size
    return {position.x, position.y, size.x, size.y}
}

SheetSpriteUpdate :: proc(sheets: []Sheet, sprite: ^SheetSprite, delta_time: f32) -> bool {
    return AnimatorUpdate(sheets, &sprite.animator, delta_time)
}

// The rectangle on the screen (position and the size of the frame) and the rectangle on the texture
SheetSpriteFrame :: proc(sheets: []Sheet, sprite: ^SheetSprite) -> (sprite_rect: rectf, texture_rect: rectf) {
    texture_rect = AnimatorFrame(sheets, sprite.animator)
    sprite_rect.xy = sprite.position
    sprite_rect.zw = texture_rect.zw
    return
}
