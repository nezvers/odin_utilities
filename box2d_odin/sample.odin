package box2d_odin

// Framework agnostic port of the Box2D samples application (box2d/samples/sample.cpp, main.cpp).
// A Sample is a set of callbacks that is registered once (usually with @(init)), SampleHost runs the selected one:
// world creation, stepping, mouse joint, camera, debug drawing, browser and controls panels.
// The demo of each framework only fills Input, provides Backend and a b2.DebugDraw (see raylib/ and karl2d/ glue).

import "core:fmt"
import "core:math"
import b2 "vendor:box2d"

MAX_SAMPLES :: 256
SCREEN_TEXT_LINES :: 32

Sample :: struct {
    category: string,
    name: string,
    // Build bodies. World is created by the host before each call. Use SetCamera to place the view
    create: proc(ctx: ^SampleContext),
    // Called every frame before the world step, `dt` is the time step that will be simulated (0 when paused)
    step: proc(ctx: ^SampleContext, dt: f32),
    // Called after the world is drawn: extra drawing and ScreenText
    draw: proc(ctx: ^SampleContext),
    // Immediate mode controls for the right panel
    controls: proc(ctx: ^SampleContext),
    keyboard: proc(ctx: ^SampleContext, key: Key),
    mouse_down: proc(ctx: ^SampleContext, point: Vec2, button: MouseButton),
    mouse_up: proc(ctx: ^SampleContext, point: Vec2, button: MouseButton),
    mouse_move: proc(ctx: ^SampleContext, point: Vec2),
    // Called before the world is destroyed
    destroy: proc(ctx: ^SampleContext),
}

SampleContext :: struct {
    world: b2.WorldId,
    camera: Camera,
    input: ^Input,
    ui: ^Ui,
    debug_draw: ^b2.DebugDraw,

    hertz: f32,
    sub_steps: i32,
    pause: bool,
    single_step: int,
    enable_sleep: bool,
    enable_warm_starting: bool,
    enable_continuous: bool,
    step_count: int,
    did_step: bool,

    mouse_body: b2.BodyId,
    mouse_joint: b2.JointId,
    mouse_point: Vec2,
    mouse_force_scale: f32,

    text: [SCREEN_TEXT_LINES][160]byte,
    text_length: [SCREEN_TEXT_LINES]int,
    text_count: int,

    home_center: Vec2,
    home_scale: f32,
}

SampleRegistry :: struct {
    samples: [MAX_SAMPLES]Sample,
    count: int,
}

registry: SampleRegistry

// Usually called from an @(init) proc of a sample file
RegisterSample :: proc "contextless" (sample: Sample) {
    if registry.count >= MAX_SAMPLES { return }
    registry.samples[registry.count] = sample
    registry.count += 1
}

SampleCount :: proc() -> int {
    return registry.count
}

GetSample :: proc(index: int) -> ^Sample {
    return &registry.samples[index]
}

// Place the view. `zoom` is half of the visible height in world units, like Camera::m_zoom in the C++ samples
SetCamera :: proc(ctx: ^SampleContext, center: Vec2, zoom: f32) {
    ctx.camera.center = center
    ctx.camera.scale = ctx.camera.size.y * 0.5 / zoom
    ctx.home_center = center
    ctx.home_scale = ctx.camera.scale
}

// Text drawn at the top of the view, call every frame from Sample.draw. Equivalent of DrawScreenTextLine
ScreenText :: proc(ctx: ^SampleContext, format: string, args: ..any) {
    if ctx.text_count >= SCREEN_TEXT_LINES { return }
    text: string = fmt.bprintf(ctx.text[ctx.text_count][:len(ctx.text[0]) - 1], format, ..args)
    ctx.text_length[ctx.text_count] = len(text)
    ctx.text_count += 1
}

// Drawing helpers that go through the DebugDraw of the framework glue
DrawLine :: proc(ctx: ^SampleContext, p1: Vec2, p2: Vec2, color: b2.HexColor) {
    ctx.debug_draw.DrawLineFcn(p1, p2, color, ctx.debug_draw.userContext)
}

DrawPoint :: proc(ctx: ^SampleContext, p: Vec2, size: f32, color: b2.HexColor) {
    ctx.debug_draw.DrawPointFcn(p, size, color, ctx.debug_draw.userContext)
}

DrawCircle :: proc(ctx: ^SampleContext, center: Vec2, radius: f32, color: b2.HexColor) {
    ctx.debug_draw.DrawCircleFcn(center, radius, color, ctx.debug_draw.userContext)
}

DrawSolidCircle :: proc(ctx: ^SampleContext, transform: b2.Transform, radius: f32, color: b2.HexColor) {
    ctx.debug_draw.DrawSolidCircleFcn(transform, {}, radius, color, ctx.debug_draw.userContext)
}

DrawPolygon :: proc(ctx: ^SampleContext, vertices: []Vec2, color: b2.HexColor) {
    ctx.debug_draw.DrawPolygonFcn(b2.Transform{q = b2.Rot{1, 0}}, raw_data(vertices), i32(len(vertices)), color, ctx.debug_draw.userContext)
}

DrawTransform :: proc(ctx: ^SampleContext, transform: b2.Transform) {
    ctx.debug_draw.DrawTransformFcn(transform, ctx.debug_draw.userContext)
}

DrawBounds :: proc(ctx: ^SampleContext, aabb: b2.AABB, color: b2.HexColor) {
    ctx.debug_draw.DrawBoundsFcn(aabb, color, ctx.debug_draw.userContext)
}

DrawString :: proc(ctx: ^SampleContext, p: Vec2, color: b2.HexColor, format: string, args: ..any) {
    buffer: [128]byte
    text: string = fmt.bprintf(buffer[:len(buffer) - 1], format, ..args)
    buffer[len(text)] = 0
    ctx.debug_draw.DrawStringFcn(p, cstring(raw_data(buffer[:])), color, ctx.debug_draw.userContext)
}

// ------------------------------------------------------------------------------------------------
// Host
// ------------------------------------------------------------------------------------------------

BROWSER_WIDTH :: 210
CONTROLS_WIDTH :: 230

SampleHost :: struct {
    backend: Backend,
    input: Input,
    ui: Ui,
    debug_draw: b2.DebugDraw,       // filled by the framework glue (InitDebugDraw)
    ctx: SampleContext,
    selected: int,
    screen: Vec2,
    browser_scroll: f32,
    margin_top: f32,        // keeps the controls panel below demo buttons
    show_ui: bool,
    draw_joints: bool,
}

// Backend, then debug draw glue: glue.InitDebugDraw(&host.debug_draw, &host.ctx.camera)
HostInit :: proc(host: ^SampleHost, backend: Backend, screen: Vec2, selected: int = 0) {
    host^ = {}
    host.backend = backend
    host.screen = screen
    host.show_ui = true
    host.selected = selected
    UiInit(&host.ui, &host.backend, &host.input)

    ctx: ^SampleContext = &host.ctx
    ctx.input = &host.input
    ctx.ui = &host.ui
    ctx.debug_draw = &host.debug_draw
    ctx.camera = {center = {0, 10}, scale = 20, size = screen}
    ctx.hertz = 60
    ctx.sub_steps = 4
    ctx.enable_sleep = true
    ctx.enable_warm_starting = true
    ctx.enable_continuous = true
    ctx.mouse_force_scale = 100
}

HostShutdown :: proc(host: ^SampleHost) {
    DestroySampleWorld(&host.ctx, GetSample(host.selected))
}

HostSelect :: proc(host: ^SampleHost, index: int) {
    if SampleCount() == 0 { return }
    ctx: ^SampleContext = &host.ctx
    if b2.World_IsValid(ctx.world) {
        DestroySampleWorld(ctx, GetSample(host.selected))
    }
    host.selected = (index + SampleCount()) % SampleCount()
    CreateSampleWorld(ctx, GetSample(host.selected))
}

@(private="file")
DestroySampleWorld :: proc(ctx: ^SampleContext, sample: ^Sample) {
    if !b2.World_IsValid(ctx.world) { return }
    if sample.destroy != nil { sample.destroy(ctx) }
    b2.DestroyWorld(ctx.world)
    ctx.world = {}
    ctx.mouse_body = {}
    ctx.mouse_joint = {}
}

@(private="file")
CreateSampleWorld :: proc(ctx: ^SampleContext, sample: ^Sample) {
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.enableSleep = ctx.enable_sleep
    ctx.world = b2.CreateWorld(world_def)
    ctx.step_count = 0
    ctx.did_step = false
    ctx.single_step = 0
    ctx.pause = false
    SetCamera(ctx, {0, 10}, 15)
    RandomReset()
    if sample.create != nil { sample.create(ctx) }
}

// One frame: input, simulation, drawing and UI. Fill host.input and host.screen before calling.
HostFrame :: proc(host: ^SampleHost, dt: f32) {
    if SampleCount() == 0 { return }
    ctx: ^SampleContext = &host.ctx
    input: ^Input = &host.input
    if !b2.World_IsValid(ctx.world) {
        HostSelect(host, host.selected)
    }
    sample: ^Sample = GetSample(host.selected)

    ctx.camera.size = host.screen
    ctx.text_count = 0

    over_ui: bool = host.show_ui && (input.mouse.x < BROWSER_WIDTH || input.mouse.x > host.screen.x - CONTROLS_WIDTH)

    HostInput(host, sample, over_ui)

    // Simulation
    time_step: f32 = 0
    if !ctx.pause || ctx.single_step > 0 {
        time_step = 1.0 / ctx.hertz if ctx.hertz > 0 else 0
        ctx.single_step = max(0, ctx.single_step - 1)
    }

    UpdateMouseJoint(ctx, time_step)
    if sample.step != nil { sample.step(ctx, time_step) }

    ctx.debug_draw.drawingBounds = CameraBounds(&ctx.camera)
    b2.World_EnableSleeping(ctx.world, ctx.enable_sleep)
    b2.World_EnableWarmStarting(ctx.world, ctx.enable_warm_starting)
    b2.World_EnableContinuous(ctx.world, ctx.enable_continuous)
    if time_step > 0 {
        b2.World_Step(ctx.world, time_step, ctx.sub_steps)
        ctx.step_count += 1
    }
    ctx.did_step = time_step > 0

    b2.World_Draw(ctx.world, ctx.debug_draw)
    if sample.draw != nil { sample.draw(ctx) }

    if host.show_ui {
        HostUi(host, sample)
    }
    HostText(host)
}

@(private="file")
HostInput :: proc(host: ^SampleHost, sample: ^Sample, over_ui: bool) {
    ctx: ^SampleContext = &host.ctx
    input: ^Input = &host.input
    world_point: Vec2 = CameraScreenToWorld(&ctx.camera, input.mouse)

    if input.key_pressed[.R] { HostSelect(host, host.selected); return }
    if input.key_pressed[.P] { ctx.pause = !ctx.pause }
    if input.key_pressed[.O] { ctx.pause = true; ctx.single_step += 1 }
    if input.key_pressed[.LEFT] { HostSelect(host, host.selected - 1); return }
    if input.key_pressed[.RIGHT] { HostSelect(host, host.selected + 1); return }
    if input.key_pressed[.TAB] { host.show_ui = !host.show_ui }

    // Camera: drag with right or middle mouse, wheel zoom
    if !over_ui {
        if input.mouse_down[.RIGHT] || input.mouse_down[.MIDDLE] {
            CameraPan(&ctx.camera, input.mouse_delta)
        }
        if input.wheel != 0 {
            CameraZoomAt(&ctx.camera, input.mouse, 1.1 if input.wheel > 0 else 1 / 1.1)
        }
    }
    if input.key_pressed[.Z] { ctx.camera.center = ctx.home_center; ctx.camera.scale = ctx.home_scale }

    for key in Key {
        if key != .NONE && input.key_pressed[key] && sample.keyboard != nil {
            sample.keyboard(ctx, key)
        }
    }

    for button in MouseButton {
        if input.mouse_pressed[button] && !over_ui {
            MouseDownDefault(ctx, world_point, button)
            if sample.mouse_down != nil { sample.mouse_down(ctx, world_point, button) }
        }
        if input.mouse_released[button] {
            MouseUpDefault(ctx, button)
            if sample.mouse_up != nil { sample.mouse_up(ctx, world_point, button) }
        }
    }
    if input.mouse_delta != {} {
        ctx.mouse_point = world_point
        if sample.mouse_move != nil { sample.mouse_move(ctx, world_point) }
    }
}

// ------------------------------------------------------------------------------------------------
// Mouse joint, port of Sample::MouseDown/MouseUp/Step
// ------------------------------------------------------------------------------------------------

@(private="file")
QueryContext :: struct {
    point: Vec2,
    body: b2.BodyId,
}

@(private="file")
QueryCallback :: proc "c" (shape: b2.ShapeId, user_context: rawptr) -> bool {
    query: ^QueryContext = cast(^QueryContext)user_context
    body: b2.BodyId = b2.Shape_GetBody(shape)
    if b2.Body_GetType(body) != .dynamicBody {
        return true
    }
    if b2.Shape_TestPoint(shape, query.point) {
        query.body = body
        return false
    }
    return true
}

@(private="file")
MouseDownDefault :: proc(ctx: ^SampleContext, point: Vec2, button: MouseButton) {
    if button != .LEFT || b2.Joint_IsValid(ctx.mouse_joint) {
        return
    }

    ctx.mouse_point = point
    delta: Vec2 = {0.001, 0.001}
    box: b2.AABB = {point - delta, point + delta}
    query: QueryContext = {point = point}
    _ = b2.World_OverlapAABB(ctx.world, point, box, b2.DefaultQueryFilter(), QueryCallback, &query)
    if !b2.Body_IsValid(query.body) {
        return
    }

    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .kinematicBody
    body_def.position = point
    body_def.enableSleep = false
    ctx.mouse_body = b2.CreateBody(ctx.world, body_def)

    joint_def: b2.MotorJointDef = b2.DefaultMotorJointDef()
    joint_def.base.bodyIdA = ctx.mouse_body
    joint_def.base.bodyIdB = query.body
    joint_def.base.localFrameB.p = b2.Body_GetLocalPoint(query.body, point)
    joint_def.linearHertz = 7.5
    joint_def.linearDampingRatio = 1

    mass_data: b2.MassData = b2.Body_GetMassData(query.body)
    gravity: f32 = b2.Length(b2.World_GetGravity(ctx.world))
    mg: f32 = mass_data.mass * gravity
    joint_def.maxSpringForce = ctx.mouse_force_scale * mg
    if mass_data.mass > 0 {
        // This acts like angular friction
        lever: f32 = math.sqrt(mass_data.rotationalInertia / mass_data.mass)
        joint_def.maxVelocityTorque = 0.25 * lever * mg
    }
    ctx.mouse_joint = b2.CreateMotorJoint(ctx.world, joint_def)
}

@(private="file")
MouseUpDefault :: proc(ctx: ^SampleContext, button: MouseButton) {
    if button != .LEFT || !b2.Joint_IsValid(ctx.mouse_joint) {
        return
    }
    b2.DestroyJoint(ctx.mouse_joint)
    ctx.mouse_joint = {}
    b2.DestroyBody(ctx.mouse_body)
    ctx.mouse_body = {}
}

@(private="file")
UpdateMouseJoint :: proc(ctx: ^SampleContext, time_step: f32) {
    if ctx.mouse_body != {} && !b2.Joint_IsValid(ctx.mouse_joint) {
        // The world or attached body was destroyed
        ctx.mouse_joint = {}
        if b2.Body_IsValid(ctx.mouse_body) {
            b2.DestroyBody(ctx.mouse_body)
        }
        ctx.mouse_body = {}
    }
    if b2.Body_IsValid(ctx.mouse_body) && time_step > 0 {
        b2.Body_SetTargetTransform(ctx.mouse_body, {ctx.mouse_point, {1, 0}}, time_step, true)
    }
}

// ------------------------------------------------------------------------------------------------
// Panels
// ------------------------------------------------------------------------------------------------

@(private="file")
HostUi :: proc(host: ^SampleHost, sample: ^Sample) {
    ctx: ^SampleContext = &host.ctx
    ui: ^Ui = &host.ui
    input: ^Input = &host.input

    // Sample browser
    ui.font_size = 15
    ui.row_height = 21
    browser: Rect = {0, 0, BROWSER_WIDTH, host.screen.y}
    if RectContains(browser, input.mouse) {
        host.browser_scroll = clamp(host.browser_scroll - input.wheel * 42, 0, 100000)
    }
    UiBegin(ui, browser, "Samples (arrows, R restart)")
    ui.cursor.y -= host.browser_scroll
    last_category: string
    for i in 0..<SampleCount() {
        entry: ^Sample = GetSample(i)
        if entry.category != last_category {
            last_category = entry.category
            UiLabel(ui, entry.category, UI_COLOR_TITLE)
        }
        // Only widgets that are inside of the panel react
        if ui.cursor.y > 24 && ui.cursor.y < host.screen.y {
            if UiButton(ui, entry.name, i == host.selected) {
                HostSelect(host, i)
                return
            }
        } else {
            ui.cursor.y += ui.row_height + 3
        }
    }

    // Controls of the sample and world settings
    controls: Rect = {host.screen.x - CONTROLS_WIDTH, host.margin_top, CONTROLS_WIDTH, host.screen.y - host.margin_top}
    UiBegin(ui, controls, sample.name)
    if sample.controls != nil {
        sample.controls(ctx)
        UiSpace(ui)
    }
    UiLabel(ui, "World", UI_COLOR_TITLE)
    UiSlider(ui, "Hertz", &ctx.hertz, 30, 240)
    UiSliderInt(ui, "Sub-steps", &ctx.sub_steps, 1, 8)
    UiCheckbox(ui, "Sleep", &ctx.enable_sleep)
    UiCheckbox(ui, "Warm starting", &ctx.enable_warm_starting)
    UiCheckbox(ui, "Continuous", &ctx.enable_continuous)
    UiCheckbox(ui, "Pause (P) / step (O)", &ctx.pause)
    UiLabel(ui, "Draw", UI_COLOR_TITLE)
    UiCheckbox(ui, "Shapes", &ctx.debug_draw.drawShapes)
    UiCheckbox(ui, "Joints", &ctx.debug_draw.drawJoints)
    UiCheckbox(ui, "Joint extras", &ctx.debug_draw.drawJointExtras)
    UiCheckbox(ui, "AABBs", &ctx.debug_draw.drawBounds)
    UiCheckbox(ui, "Contact points", &ctx.debug_draw.drawContacts)
    UiCheckbox(ui, "Contact normals", &ctx.debug_draw.drawContactNormals)
    UiCheckbox(ui, "Mass", &ctx.debug_draw.drawMass)
    UiSpace(ui)
    UiLabel(ui, "Tab hide UI, Z reset view")
    UiLabel(ui, "RMB drag pan, wheel zoom")
}

@(private="file")
HostText :: proc(host: ^SampleHost) {
    ctx: ^SampleContext = &host.ctx
    x: f32 = (BROWSER_WIDTH + 8) if host.show_ui else 8
    y: f32 = 6
    for i in 0..<ctx.text_count {
        host.backend.text(string(ctx.text[i][:ctx.text_length[i]]), {x, y}, 16, {255, 255, 255, 255})
        y += 20
    }
    buffer: [96]byte
    status: string = fmt.bprintf(buffer[:], "bodies %d  step %d%s", b2.World_GetAwakeBodyCount(ctx.world), ctx.step_count, "  PAUSED" if ctx.pause else "")
    host.backend.text(status, {x, host.screen.y - 22}, 14, {200, 200, 200, 255})
}

// Destroy the world and create a new empty one, without calling Sample.create (CreateWorld in the C++ samples)
SampleRecreateWorld :: proc(ctx: ^SampleContext) {
    if b2.World_IsValid(ctx.world) {
        b2.DestroyWorld(ctx.world)
    }
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.enableSleep = ctx.enable_sleep
    ctx.world = b2.CreateWorld(world_def)
    ctx.mouse_body = {}
    ctx.mouse_joint = {}
}
