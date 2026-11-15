#+build !js
// Tests of sheet.odin. They are in their own file because the library is used by games with a web build, and core:testing does not
// compile for js_wasm32.
package sprite

import "core:testing"

// frames 0-2: walk (3 frames), 3-4: jump (2), 5: one still frame
@(private="file")
positions: [6]vec2 = {{0, 0}, {16, 0}, {32, 0}, {0, 16}, {16, 16}, {32, 16}}
@(private="file")
clips: [3]Clip = {{0, 3}, {3, 2}, {5, 1}}

@(private="file")
test_sheets :: proc() -> [1]Sheet {
    return {{frame_size = {16, 16}, frames = positions[:], clips = clips[:]}}
}

@(test)
test_animator_advances_and_wraps :: proc(t: ^testing.T) {
    sheets: [1]Sheet = test_sheets()
    animator: Animator = {frame_rate = 10}

    testing.expect(t, !AnimatorUpdate(sheets[:], &animator, 0.05))                          // half a frame
    testing.expect_value(t, animator.image, u16(0))
    AnimatorUpdate(sheets[:], &animator, 0.05)
    testing.expect_value(t, animator.image, u16(1))
    AnimatorUpdate(sheets[:], &animator, 0.1)
    testing.expect_value(t, animator.image, u16(2))
    wrapped: bool = AnimatorUpdate(sheets[:], &animator, 0.1)
    testing.expect_value(t, animator.image, u16(0))                                         // back to the start
    testing.expect(t, wrapped, "it says it started over")

    AnimatorUpdate(sheets[:], &animator, 0.35)                                              // several frames in one update keep the fraction
    testing.expect_value(t, animator.image, u16(0))                                         // 3 frames on a loop of 3
    testing.expect(t, abs(animator.time - 0.5) < 1e-4)
}

@(test)
test_changing_clip_starts_from_the_first_frame :: proc(t: ^testing.T) {
    sheets: [1]Sheet = test_sheets()
    animator: Animator = {frame_rate = 10}
    AnimatorUpdate(sheets[:], &animator, 0.15)
    AnimatorChange(&animator, 1)
    testing.expect_value(t, animator.clip, u16(1))
    testing.expect_value(t, animator.image, u16(0))
    testing.expect_value(t, animator.time, f32(0))
    testing.expect_value(t, AnimatorFrame(sheets[:], animator), rectf{0, 16, 16, 16})

    AnimatorUpdate(sheets[:], &animator, 0.1)
    AnimatorUpdate(sheets[:], &animator, 0.1)
    testing.expect_value(t, animator.image, u16(0))                                         // this clip has 2 frames
    AnimatorChange(&animator, 2)
    AnimatorUpdate(sheets[:], &animator, 1)
    testing.expect_value(t, animator.image, u16(0))                                         // a clip of one frame stays on it
    testing.expect_value(t, AnimatorFrame(sheets[:], animator), rectf{32, 16, 16, 16})
}

@(test)
test_one_shot_animation_stops_on_the_last_frame :: proc(t: ^testing.T) {
    sheets: [1]Sheet = test_sheets()
    animator: Animator = {frame_rate = 10}                                                  // an effect of 3 frames
    testing.expect(t, !AnimatorUpdateOnce(sheets[:], &animator, 0.1))
    testing.expect_value(t, animator.image, u16(1))
    testing.expect(t, !AnimatorUpdateOnce(sheets[:], &animator, 0.1))
    testing.expect_value(t, animator.image, u16(2))
    testing.expect(t, AnimatorUpdateOnce(sheets[:], &animator, 0.1), "past the last frame: over")
    testing.expect_value(t, animator.image, u16(2))                                         // it shows the last frame, it does not wrap

    big: Animator = {frame_rate = 10}
    testing.expect(t, AnimatorUpdateOnce(sheets[:], &big, 5), "a long frame skips to the end")
    testing.expect_value(t, big.image, u16(2))
}

@(test)
test_sprite_frame_rects_and_update :: proc(t: ^testing.T) {
    sheets: [1]Sheet = test_sheets()
    sprite: SheetSprite = {animator = {frame_rate = 10}, position = {100, 50}, scale = {1, 1}}
    SheetSpriteUpdate(sheets[:], &sprite, 0.1)
    screen, texture := SheetSpriteFrame(sheets[:], &sprite)
    testing.expect_value(t, texture, rectf{16, 0, 16, 16})
    testing.expect_value(t, screen, rectf{100, 50, 16, 16})
}

@(test)
test_bad_data_gives_nothing_instead_of_a_crash :: proc(t: ^testing.T) {
    sheets: [1]Sheet = test_sheets()
    testing.expect_value(t, len(ClipFrames(sheets[:], {sheet = 5})), 0)                      // no such sheet
    testing.expect_value(t, len(ClipFrames(sheets[:], {clip = 9})), 0)                       // no such clip
    testing.expect_value(t, AnimatorFrame(sheets[:], {sheet = 5}), rectf{})
    testing.expect_value(t, AnimatorFrame(nil, {}), rectf{})

    broken: [1]Sheet = {{frame_size = {8, 8}, frames = positions[:2], clips = clips[:1]}}    // the clip wants 3 frames, there are 2
    testing.expect_value(t, len(ClipFrames(broken[:], {})), 0)
    animator: Animator = {frame_rate = 100}
    AnimatorUpdate(broken[:], &animator, 1)                                                  // no division by zero
    testing.expect(t, AnimatorUpdateOnce(broken[:], &animator, 1), "nothing to play counts as over")

    empty: [1]Sheet = {{clips = {{0, 0}}}}
    AnimatorUpdate(empty[:], &animator, 1)
    testing.expect_value(t, animator.image, u16(0))
}

@(test)
test_an_animator_is_plain_data :: proc(t: ^testing.T) {
    // a sprite holds numbers only: it can be copied, overridden field by field, saved and reloaded
    sprite: SheetSprite = {animator = {sheet = 2, clip = 3, image = 1, frame_rate = 8, time = 0.25}, position = {1, 2}, scale = {1, -1}}
    copy_of_it: SheetSprite = sprite
    copy_of_it.animator.clip = 0
    testing.expect_value(t, sprite.animator.clip, u16(3))
    testing.expect_value(t, size_of(Animator), 16)
    testing.expect_value(t, size_of(SheetSprite), 16 + 8 * 4 + 4)
}
