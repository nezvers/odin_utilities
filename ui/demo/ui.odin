package demo

import "core:log"
import "vendor:raylib"
import ui "../"
Element :: ui.Element
import "core:strings"

ElementContext :: struct {
    cursor: Vector2,
    input_down: bool,
    delta_time: f32,
    down: ^Element, // like slider drag outside it's rect or not released button press
    hover: ^Element,
    pressed: ^Element,
    released: ^Element,
    selected: ^Element,
}

button_update_events :: proc(element: ^Element) {
    button_update(element)
    changes: ui.ElementStatesSet = element.state - element.previous_state

    if changes == {} {return}
    if .Pressed in changes {
        log.debug("pressed")
    }
    if .Down in changes {
        log.debug("down")
    }
    if .Released in changes {
        log.debug("released")
    }
    if .Selected in changes {
        log.debug("selected")
    }
}

// Basis behaviour for ui interactability
button_update :: proc(element: ^Element) {
    assert(element.ctx != nil)
    ctx: ^ElementContext = cast(^ElementContext)element.ctx

    if ui.IsHover(ctx.cursor, element.rect) {
        if ctx.hover == nil {
            // First one to claim hover
            ctx.hover = element
        }
        if .Hover not_in element.state {
            element.state += {.Hover}
            // TODO: Trigger event on new hover
        }
    } else {
        if .Hover in element.state {
            element.state -= {.Hover}
        }
    }

    if .Hover in element.state {
        if ctx.input_down {
            if ctx.down == nil && (.Down not_in element.state) {
                assert(.Pressed not_in element.state)
                element.state += {.Pressed, .Down}
                ctx.down = element
                ctx.pressed = element
                // TODO: Trigger events

                if ctx.selected != element {
                    element.state += {.Selected}
                    if ctx.selected != nil {
                        ctx.selected.state -= {.Selected}
                    }
                    ctx.selected = element
                    // TODO: Trigger events
                }
            } else {
                // Not possible to start new pressed & down
                if .Pressed in element.state {
                    element.state -= {.Pressed}
                }
                if ctx.down == element {
                    // TODO: Continued hold timer
                }
            }
        } else {
            // Not input_down
            // TODO: Release on button
            if ctx.down == element {
                element.state -= {.Down}
                element.state += {.Released}
                ctx.down = nil
                // TODO: Release on-button
            } else 
            if .Down in element.state {
                element.state -= {.Down}
                element.state += {.Released}
                // TODO: Multi-button selection from ctx.down to one under cursor
            }
        }
    } else {
        // Not hovering
        if .Pressed in element.state {
            element.state -= {.Pressed}
        }
        if .Down in element.state {
            if ctx.down == element {
                // TODO: handle held outside
                if !ctx.input_down {
                    element.state -= {.Down}
                    element.state += {.Released}
                    ctx.down = nil
                    // TODO: Release off-button 
                }
            } else {
                element.state -= {.Down}
                element.state += {.Released}
                // TODO: Trigger event
            }
        }
    }
}

button_draw :: proc(element: ^Element) {
    assert(element.ctx != nil)

    bg_color: Color = raylib.LIGHTGRAY
    if .Down in element.state {
        bg_color -= {20, 20, 20, 0}
    }
    raylib.DrawRectangleRec(transmute(Rectangle)element.rect, bg_color)

    if .Selected in element.state {
        selection: ui.rectf = element.rect
        selection.xy += selection.ww * 0.1
        selection.zw -= selection.ww * (0.1 * 2)
        raylib.DrawRectangleLinesEx(transmute(Rectangle)selection, 1, raylib.GRAY)
    }

    if len(element.text) > 0 {
        font_size: i32 = cast(i32)(element.rect.w * 0.8)
        text:cstring = strings.unsafe_string_to_cstring(element.text)
        text_size:i32 = raylib.MeasureText(text, font_size)
        text_position:Vector2 = element.rect.xy + (element.rect.zw - {cast(f32)text_size, cast(f32)font_size}) * 0.5

        text_color: Color = raylib.BLACK
        if ui.ElementStatesSet.Hover in element.state {
            text_color = raylib.WHITE
        }
        raylib.DrawText(text, cast(i32)text_position.x, cast(i32)text_position.y, font_size, text_color)
    }
}

selected_set :: proc(ctx: ^ElementContext, element: ^Element) {
    assert(element != nil)
    if ctx.selected == nil {
        ctx.selected = element
        element.state += {.Selected}
        return
    }
    
    from: ^Element = ctx.selected
    to: ^Element = element
    from.state -= {.Selected}
    to.state += {.Selected}
    ctx.selected = to
}

selected_hold :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil {return}
    ctx.cursor = ctx.selected.rect.xy + ctx.selected.rect.zw * 0.5
    ctx.input_down = true
}

selected_next :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil { return }
    if ctx.selected.neighbours.next == nil { return }
    selected_transfer(ctx, ctx.selected, ctx.selected.neighbours.next)
}

selected_previous :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil { return }
    if ctx.selected.neighbours.previous == nil { return }
    selected_transfer(ctx, ctx.selected, ctx.selected.neighbours.previous)
}

selected_right :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil { return }
    if ctx.selected.neighbours.right == nil { return }
    selected_transfer(ctx, ctx.selected, ctx.selected.neighbours.right)
}

selected_left :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil { return }
    if ctx.selected.neighbours.left == nil { return }
    selected_transfer(ctx, ctx.selected, ctx.selected.neighbours.left)
}

selected_up :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil { return }
    if ctx.selected.neighbours.up == nil { return }
    selected_transfer(ctx, ctx.selected, ctx.selected.neighbours.up)
}

selected_down :: proc(ctx: ^ElementContext) {
    if ctx.selected == nil { return }
    if ctx.selected.neighbours.down == nil { return }
    selected_transfer(ctx, ctx.selected, ctx.selected.neighbours.down)
}

selected_transfer :: proc(ctx: ^ElementContext, from: ^Element, to: ^Element) {
    assert(ctx != nil)
    assert(from != nil)
    assert(to != nil)
    from.state -= {.Selected}
    to.state += {.Selected}
    ctx.selected = to
    // TODO: Trigger event
}