package demo_common

// What the demos need from a framework: text drawn by the font library. A demo fills a list of requests; the glue of the framework (font_raylib, font_karl2d) turns them into draws, with an Atlas
// and a Renderer per method that it makes the first time it is asked.

import kit "../../demo_kit"
import font "../"

MAX_TEXT_REQUESTS :: 64

TextRequest :: struct {
    text: string,
    position: kit.Vec2,         // the baseline starts here, in pixels
    size: f32,                  // pixels to the em
    color: kit.Color,
    method: font.Method,
}

// Draws the requests with the face. Set by the demo of a framework before it runs the demos (nil: the demos draw without text, as in the headless test).
TextDrawer :: proc(ctx: ^kit.Context, face: ^font.Font, requests: []TextRequest)
text_drawer: TextDrawer
