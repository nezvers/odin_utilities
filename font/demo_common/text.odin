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

// Rich text: markup that is parsed and laid out by the demo (font.RichParse, font.RichLayout) and drawn by the glue at a time. A request has the text and where it goes.
RichRequest :: struct {
    rich: ^font.RichText,
    position: kit.Vec2,         // the top left corner of the text
    time: f32,                  // seconds, the demo gives the frame counted in 1/60 so that a test sees the same picture each time
    options: font.RichDrawOptions,
    method: font.Method,
}

RichDrawer :: proc(ctx: ^kit.Context, face: ^font.Font, requests: []RichRequest)
rich_drawer: RichDrawer
