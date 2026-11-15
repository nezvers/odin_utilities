package drag_drop

// Dragging a rectangle with the mouse: grab it where it was clicked, keep that offset while it moves, let go on release.
// Framework agnostic: the caller gives the mouse position and the button state, and does the drawing.
//
//     item: DragRect = {rect = {40, 40, 32, 32}}
//     // each frame
//     if mouse_pressed && DragHit(item, mouse) { DragBegin(&item, mouse) }
//     if item.dragging { DragMove(&item, mouse); if mouse_released { DragEnd(&item) } }

Vec2 :: [2]f32
Rect :: [4]f32          // x, y, width, height

DragRect :: struct {
    rect: Rect,
    offset: Vec2,       // from the mouse to the top left corner, kept while dragging
    dragging: bool,
}

// Is the point inside of the rectangle
DragHit :: proc(item: DragRect, point: Vec2) -> bool {
    return point.x >= item.rect.x && point.x <= item.rect.x + item.rect.z && point.y >= item.rect.y && point.y <= item.rect.y + item.rect.w
}

// Grab the item at the mouse: it keeps its distance to the mouse from now on
DragBegin :: proc(item: ^DragRect, mouse: Vec2) {
    item.offset = {item.rect.x, item.rect.y} - mouse
    item.dragging = true
}

// Move the grabbed item with the mouse
DragMove :: proc(item: ^DragRect, mouse: Vec2) {
    item.rect.x = mouse.x + item.offset.x
    item.rect.y = mouse.y + item.offset.y
}

DragEnd :: proc(item: ^DragRect) {
    item.dragging = false
}

// The first item under the mouse, -1 when there is none. The last one is drawn on top, so it is searched from the end.
DragFind :: proc(items: []DragRect, mouse: Vec2) -> int {
    for i := len(items) - 1; i >= 0; i -= 1 {
        if DragHit(items[i], mouse) { return i }
    }
    return -1
}

// Put the item on a rectangle, a slot of an inventory
DragSnapTo :: proc(item: ^DragRect, target: Rect) {
    item.rect.x = target.x
    item.rect.y = target.y
}
