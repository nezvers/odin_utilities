#+build !js
// Tests of sprite.odin. They are in their own file because the library is used by games with a web build, and core:testing does not
// compile for js_wasm32.
package sprite

import "core:testing"

@(private="file")
make_walk :: proc(frames: ^[2]Frames, positions: ^[6]vec2, pointers: ^[2]^Frames) -> AnimationSet {
    positions^ = {{0, 0}, {16, 0}, {32, 0}, {0, 16}, {16, 16}, {32, 16}}
    frames[0] = {data = positions[0:3], size = {16, 16}}
    frames[1] = {data = positions[3:5], size = {16, 16}}
    pointers^ = {&frames[0], &frames[1]}
    return {frames = pointers[:], frame_rate = 10}
}

@(test)
test_animation_advances_and_wraps :: proc(t: ^testing.T) {
    frames: [2]Frames
    positions: [6]vec2
    pointers: [2]^Frames
    set: AnimationSet = make_walk(&frames, &positions, &pointers)

    UpdateAnimation(&set, 0.05)                                                            // half a frame
    testing.expect_value(t, set.image_index, u32(0))
    UpdateAnimation(&set, 0.05)
    testing.expect_value(t, set.image_index, u32(1))
    UpdateAnimation(&set, 0.1)
    testing.expect_value(t, set.image_index, u32(2))
    UpdateAnimation(&set, 0.1)
    testing.expect_value(t, set.image_index, u32(0))                                       // wraps to the start

    UpdateAnimation(&set, 0.35)                                                            // several frames in one update keep the fraction
    testing.expect_value(t, set.image_index, u32(0))                                       // 3 frames on a loop of 3
    testing.expect(t, abs(set.time - 0.5) < 1e-4)
}

@(test)
test_animation_change_and_frame_rect :: proc(t: ^testing.T) {
    frames: [2]Frames
    positions: [6]vec2
    pointers: [2]^Frames
    set: AnimationSet = make_walk(&frames, &positions, &pointers)
    UpdateAnimation(&set, 0.1)

    ChangeAnimation(&set, 1)
    testing.expect_value(t, set.animation_index, u32(1))
    testing.expect_value(t, set.image_index, u32(0))                                       // starts from the first frame
    testing.expect_value(t, set.time, f32(0))
    testing.expect_value(t, GetAnimationFrame(&set), rectf{0, 16, 16, 16})

    UpdateAnimation(&set, 0.1)
    UpdateAnimation(&set, 0.1)
    testing.expect_value(t, set.image_index, u32(0))                                       // the second clip has only 2 frames
}

@(test)
test_sprite_frame_rects :: proc(t: ^testing.T) {
    frames: [2]Frames
    positions: [6]vec2
    pointers: [2]^Frames
    sprite: Sprite = {animation_set = make_walk(&frames, &positions, &pointers), position = {100, 50}}
    UpdateSprite(&sprite, 0.1)

    target, source := GetSpriteFrame(&sprite)
    testing.expect_value(t, source, rectf{16, 0, 16, 16})
    testing.expect_value(t, target, rectf{100, 50, 16, 16})
}
