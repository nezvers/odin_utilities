package box2d_odin

import b2 "vendor:box2d"

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
