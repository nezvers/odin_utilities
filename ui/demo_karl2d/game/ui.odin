package game

import "core:log"
import "../../../karl2d"
import ui "../../"
Element :: ui.Element

ElementContext :: struct {
    cursor: Vec2,
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

    bg_color: Color = karl2d.LIGHT_GRAY
    if .Down in element.state {
        bg_color -= {20, 20, 20, 0}
    }
    karl2d.draw_rect(transmute(Rect)element.rect, bg_color)

    if .Selected in element.state {
        selection: ui.rectf = element.rect
        selection.xy += selection.ww * 0.1
        selection.zw -= selection.ww * (0.1 * 2)
        karl2d.draw_rect_outline(transmute(Rect)selection, 1, karl2d.GRAY)
    }

    if len(element.text) > 0 {
        font_size: f32 = element.rect.w * 0.8
        text_size:Vec2 = karl2d.measure_text(element.text, font_size, karl2d.FONT_DEFAULT)
        text_position:Vec2 = element.rect.xy + (element.rect.zw - text_size) * 0.5

        text_color: Color = karl2d.BLACK
        if ui.ElementStatesSet.Hover in element.state {
            text_color = karl2d.WHITE
        }
        karl2d.draw_text(element.text, text_position, font_size, text_color, karl2d.FONT_DEFAULT)
    }
}