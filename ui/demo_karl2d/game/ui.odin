package game

import "../../../karl2d"
import ui "../../"
Element :: ui.Element
GroupComponent :: ui.GroupComponent
NeighborsComponent :: ui.NeighborsComponent
CallbackComponent :: ui.CallbackComponent

ElementContext :: struct {
    // shared
    group: ^GroupComponent,
    // individual
    neighbours: NeighborsComponent,
    callbacks: CallbackComponent,
}

// Extended button update that calls callbacks on state change
button_update_events :: proc(element: ^Element) {
    button_update(element)
    changes: ui.ElementStatesSet = element.state - element.previous_state

    if changes == {} {return}
    ctx: ^ElementContext = get_element_context(element)

    if .Pressed in changes && ctx.callbacks.pressed != nil {
        ctx.callbacks.pressed(element)
    }
    if .Down in changes && ctx.callbacks.down != nil {
        ctx.callbacks.down(element)
    }
    if .Released in changes {
        if ctx.callbacks.released != nil {
            if .Hover in element.state {
                ctx.callbacks.released(element)
            }
        }
    }
    if .Selected in changes && ctx.callbacks.selected != nil {
        ctx.callbacks.selected(element)
    }
}

// Basis behaviour for ui interactability
button_update :: proc(element: ^Element) {
    assert(element.ctx != nil)
    ctx: ^ElementContext = cast(^ElementContext)element.ctx
    group: ^GroupComponent = ctx.group

    if ui.IsHover(group.cursor, element.rect) {
        if group.hover == nil {
            // First one to claim hover
            group.hover = element
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

    if .Pressed in element.state {
        element.state -= {.Pressed}
    }
    if .Released in element.state {
        element.state -= {.Released}
    }

    if .Hover in element.state {
        if group.input_down {
            if group.down == nil && (.Down not_in element.state) {
                assert(.Pressed not_in element.state)
                element.state += {.Pressed, .Down}
                group.down = element
                group.pressed = element
                // TODO: Trigger events

                if group.selected != element {
                    element.state += {.Selected}
                    if group.selected != nil {
                        group.selected.state -= {.Selected}
                    }
                    group.selected = element
                    // TODO: Trigger events
                }
            } else {
                // Not possible to start new pressed & down
                if group.down == element {
                    // TODO: Continued hold timer or check the group.down
                }
            }
        } else {
            // Not input_down
            // TODO: Release on button
            if group.down == element {
                element.state -= {.Down}
                element.state += {.Released}
                group.down = nil
                // TODO: Release on-button
            } else 
            if .Down in element.state {
                element.state -= {.Down}
                element.state += {.Released}
                // TODO: Multi-button selection from group.down to one under cursor
            }
        }
    } else {
        // Not hovering
        if .Down in element.state {
            if group.down == element {
                // TODO: handle held outside
                if !group.input_down {
                    element.state -= {.Down}
                    element.state += {.Released}
                    group.down = nil
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
    assert(element != nil)
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

selected_set :: proc(ctx: ^GroupComponent, element: ^Element) {
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

selected_hold :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil {return}
    ctx.cursor = ctx.selected.rect.xy + ctx.selected.rect.zw * 0.5
    ctx.input_down = true
}

// Dereference pointer
get_element_context :: proc(element: ^Element)-> ^ElementContext {
    return cast(^ElementContext)element.ctx
}

selected_next :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil { return }
    if ctx.selected.ctx == nil { return }
    neighbours: ^NeighborsComponent = &get_element_context(ctx.selected).neighbours
    if neighbours.next == nil { return }
    selected_transfer(ctx, ctx.selected, neighbours.next)
}

selected_previous :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil { return }
    if ctx.selected.ctx == nil { return }
    neighbours: ^NeighborsComponent = &get_element_context(ctx.selected).neighbours
    if neighbours.previous == nil { return }
    selected_transfer(ctx, ctx.selected, neighbours.previous)
}

selected_right :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil { return }
    if ctx.selected.ctx == nil { return }
    neighbours: ^NeighborsComponent = &get_element_context(ctx.selected).neighbours
    if neighbours.right == nil { return }
    selected_transfer(ctx, ctx.selected, neighbours.right)
}

selected_left :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil { return }
    if ctx.selected.ctx == nil { return }
    neighbours: ^NeighborsComponent = &get_element_context(ctx.selected).neighbours
    if neighbours.left == nil { return }
    selected_transfer(ctx, ctx.selected, neighbours.left)
}

selected_up :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil { return }
    if ctx.selected.ctx == nil { return }
    neighbours: ^NeighborsComponent = &get_element_context(ctx.selected).neighbours
    if neighbours.up == nil { return }
    selected_transfer(ctx, ctx.selected, neighbours.up)
}

selected_down :: proc(ctx: ^GroupComponent) {
    if ctx.selected == nil { return }
    if ctx.selected.ctx == nil { return }
    neighbours: ^NeighborsComponent = &get_element_context(ctx.selected).neighbours

    if neighbours.down == nil { return }
    selected_transfer(ctx, ctx.selected, neighbours.down)
}

selected_transfer :: proc(ctx: ^GroupComponent, from: ^Element, to: ^Element) {
    assert(ctx != nil)
    assert(from != nil)
    assert(to != nil)
    from.state -= {.Selected}
    to.state += {.Selected}
    ctx.selected = to
    // TODO: Trigger event
}