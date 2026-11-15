#+build !js
package drag_drop

import "core:testing"

@(test)
test_the_item_keeps_its_offset_to_the_mouse :: proc(t: ^testing.T) {
    item: DragRect = {rect = {40, 40, 32, 32}}
    testing.expect(t, DragHit(item, {50, 50}))
    testing.expect(t, !DragHit(item, {100, 50}))
    DragBegin(&item, {50, 55})
    DragMove(&item, {150, 255})
    testing.expect_value(t, item.rect, Rect{140, 240, 32, 32})
    DragEnd(&item)
    testing.expect(t, !item.dragging)
}

@(test)
test_find_returns_the_top_item :: proc(t: ^testing.T) {
    items: [3]DragRect = {{rect = {0, 0, 50, 50}}, {rect = {20, 20, 50, 50}}, {rect = {200, 200, 10, 10}}}
    testing.expect_value(t, DragFind(items[:], {30, 30}), 1)         // two overlap, the later one is on top
    testing.expect_value(t, DragFind(items[:], {5, 5}), 0)
    testing.expect_value(t, DragFind(items[:], {205, 205}), 2)
    testing.expect_value(t, DragFind(items[:], {500, 500}), -1)
}

@(test)
test_snap_moves_to_a_slot :: proc(t: ^testing.T) {
    item: DragRect = {rect = {3, 4, 40, 40}}
    DragSnapTo(&item, {200, 85, 40, 40})
    testing.expect_value(t, item.rect, Rect{200, 85, 40, 40})
}
