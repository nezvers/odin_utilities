package box2d_odin

import b2 "vendor:box2d"
import "core:testing"

// Maps physics world (meters, y up) to screen pixels (y down).
// Pass pointer to it as DebugDraw.userContext so glue draws with the camera.
// Without a camera (nil) glue draws world units as pixels with flipped y, like the platformer demo.
Camera :: struct {
    center: Vec2,   // world position in the middle of the screen
    scale: f32,     // pixels per world unit
    size: Vec2,     // screen size in pixels
}

CameraWorldToScreen :: proc "contextless" (camera: ^Camera, point: Vec2) -> Vec2 {
    return {
        (point.x - camera.center.x) * camera.scale + camera.size.x * 0.5,
        camera.size.y * 0.5 - (point.y - camera.center.y) * camera.scale,
    }
}

CameraScreenToWorld :: proc "contextless" (camera: ^Camera, point: Vec2) -> Vec2 {
    return {
        (point.x - camera.size.x * 0.5) / camera.scale + camera.center.x,
        (camera.size.y * 0.5 - point.y) / camera.scale + camera.center.y,
    }
}

// Move the view by screen pixels, dragging the world with the pointer
CameraPan :: proc "contextless" (camera: ^Camera, screen_delta: Vec2) {
    camera.center.x -= screen_delta.x / camera.scale
    camera.center.y += screen_delta.y / camera.scale
}

// Zoom by factor and keep the world point under `screen_point` in place
CameraZoomAt :: proc "contextless" (camera: ^Camera, screen_point: Vec2, factor: f32) {
    before: Vec2 = CameraScreenToWorld(camera, screen_point)
    camera.scale = clamp(camera.scale * factor, 1, 500)
    after: Vec2 = CameraScreenToWorld(camera, screen_point)
    camera.center += before - after
}

// World AABB that is visible, for DebugDraw.drawingBounds
CameraBounds :: proc "contextless" (camera: ^Camera) -> b2.AABB {
    lower: Vec2 = CameraScreenToWorld(camera, {0, camera.size.y})
    upper: Vec2 = CameraScreenToWorld(camera, {camera.size.x, 0})
    return {lower, upper}
}

// --- Tests ---

@(private="file")
near2 :: proc(a, b: Vec2, epsilon: f32 = 1e-4) -> bool {
    return abs(a.x - b.x) <= epsilon && abs(a.y - b.y) <= epsilon
}

@(test)
test_camera_world_screen_mapping :: proc(t: ^testing.T) {
    camera: Camera = {center = {10, 5}, scale = 20, size = {800, 600}}

    testing.expect_value(t, CameraWorldToScreen(&camera, {10, 5}), Vec2{400, 300})         // the centre is the middle of the screen
    testing.expect_value(t, CameraWorldToScreen(&camera, {11, 5}), Vec2{420, 300})         // x grows to the right
    testing.expect_value(t, CameraWorldToScreen(&camera, {10, 6}), Vec2{400, 280})         // world y points up, screen y points down
    testing.expect(t, near2(CameraScreenToWorld(&camera, {420, 280}), {11, 6}))

    for point in ([]Vec2{{0, 0}, {-12.5, 33}, {100, -7}}) {
        back: Vec2 = CameraScreenToWorld(&camera, CameraWorldToScreen(&camera, point))
        testing.expect(t, near2(back, point), "a round trip returns the same point")
    }
}

@(test)
test_camera_pan_and_zoom :: proc(t: ^testing.T) {
    camera: Camera = {center = {0, 0}, scale = 10, size = {800, 600}}

    under_pointer: Vec2 = CameraScreenToWorld(&camera, {100, 100})
    CameraPan(&camera, {30, -20})                                                          // the world is dragged with the pointer
    testing.expect(t, near2(CameraWorldToScreen(&camera, under_pointer), {130, 80}))

    camera = {center = {3, 4}, scale = 10, size = {800, 600}}
    anchor: Vec2 = {650, 120}
    world_point: Vec2 = CameraScreenToWorld(&camera, anchor)
    CameraZoomAt(&camera, anchor, 2)
    testing.expect_value(t, camera.scale, f32(20))
    testing.expect(t, near2(CameraScreenToWorld(&camera, anchor), world_point), "the point under the pointer stays put")

    CameraZoomAt(&camera, anchor, 1000)
    testing.expect_value(t, camera.scale, f32(500))                                        // limits
    CameraZoomAt(&camera, anchor, 1e-6)
    testing.expect_value(t, camera.scale, f32(1))
}

@(test)
test_camera_bounds :: proc(t: ^testing.T) {
    camera: Camera = {center = {10, 5}, scale = 20, size = {800, 600}}
    bounds: b2.AABB = CameraBounds(&camera)
    testing.expect(t, near2(bounds.lowerBound, {-10, -10}))
    testing.expect(t, near2(bounds.upperBound, {30, 20}))
}
