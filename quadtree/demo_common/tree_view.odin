#+private file
package demo_common

import qt ".."
import kit "../../demo_kit"

// Draws one node of the tree: leaves as outlines that are darker the deeper they are, filled a little when they hold elements. `user` is the kit context.
@(private = "package")
drawNode :: proc(user: rawptr, rect: qt.Rect, depth: int, leaf: bool, count: int) {
    if !leaf { return }
    ctx: ^kit.Context = cast(^kit.Context)user
    shade: u8 = u8(min(200 - depth * 18, 200))
    if count > 0 { kit.DrawRect(ctx, transmute(kit.Rect)rect, kit.Color{90, 140, 230, u8(min(20 + count * 8, 90))}) }
    kit.DrawRectOutline(ctx, transmute(kit.Rect)rect, 1, kit.Color{shade, shade, shade, 255})
}
