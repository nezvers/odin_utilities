package box2d_samples

import "core:testing"
import b2 "vendor:box2d"
import b2o ".."

// Smoke test: every registered sample is created, simulated, drawn and has its controls run, without a window.

@(private="file")
null_backend: b2o.Backend = {
    rect = proc(rect: b2o.Rect, color: b2o.Color) {},
    rect_outline = proc(rect: b2o.Rect, color: b2o.Color) {},
    text = proc(text: string, position: Vec2, size: f32, color: b2o.Color) {},
    text_width = proc(text: string, size: f32) -> f32 { return 0 },
}

@(private="file")
InitNullDebugDraw :: proc(debug_draw: ^b2.DebugDraw) {
    debug_draw^ = b2.DefaultDebugDraw()
    debug_draw.DrawPolygonFcn = proc "c" (t: b2.Transform, v: [^]Vec2, n: i32, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawSolidPolygonFcn = proc "c" (t: b2.Transform, v: [^]Vec2, n: i32, r: f32, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawCircleFcn = proc "c" (p: Vec2, r: f32, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawSolidCircleFcn = proc "c" (t: b2.Transform, p: Vec2, r: f32, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawSolidCapsuleFcn = proc "c" (a: Vec2, b: Vec2, r: f32, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawLineFcn = proc "c" (a: Vec2, b: Vec2, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawTransformFcn = proc "c" (t: b2.Transform, u: rawptr) {}
    debug_draw.DrawPointFcn = proc "c" (p: Vec2, s: f32, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawStringFcn = proc "c" (p: Vec2, s: cstring, c: b2.HexColor, u: rawptr) {}
    debug_draw.DrawBoundsFcn = proc "c" (a: b2.AABB, c: b2.HexColor, u: rawptr) {}
    debug_draw.drawShapes = true
    debug_draw.drawJoints = true
    debug_draw.drawBounds = true
    debug_draw.drawContacts = true
    debug_draw.drawMass = true
    debug_draw.drawingBounds = {{-1e9, -1e9}, {1e9, 1e9}}
}

@(test)
test_all_samples_run :: proc(t: ^testing.T) {
    testing.expect(t, b2o.SampleCount() > 0)

    host: b2o.SampleHost
    b2o.HostInit(&host, null_backend, {1280, 720})
    InitNullDebugDraw(&host.debug_draw)

    for index in 0..<b2o.SampleCount() {
        sample: ^b2o.Sample = b2o.GetSample(index)
        testing.expect(t, sample.create != nil, sample.name)
        b2o.HostSelect(&host, index)
        for _ in 0..<60 {
            b2o.HostFrame(&host, 1.0 / 60)
        }
        testing.expectf(t, host.ctx.step_count == 60, "%s/%s stepped %d times", sample.category, sample.name, host.ctx.step_count)
        // Sample keyboard handlers must not break the sample, keys of the host (navigation, pause) are skipped
        for key in b2o.Key {
            if key == .NONE || key == .R || key == .P || key == .O || key == .TAB || key == .LEFT || key == .RIGHT || key == .Z {
                continue
            }
            host.input.key_pressed[key] = true
            b2o.HostFrame(&host, 1.0 / 60)
            host.input.key_pressed[key] = false
        }
        // Restart must not break the sample
        host.input.key_pressed[.R] = true
        b2o.HostFrame(&host, 1.0 / 60)
        host.input.key_pressed[.R] = false
    }
    b2o.HostShutdown(&host)
}
