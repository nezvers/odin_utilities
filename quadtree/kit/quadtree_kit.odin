// Debug drawing of the quadtrees over the demo kit (odin_utilities/demo_kit): the nodes of a tree as outlines, so a demo written against the kit shows the tree on any backend. The leaves are drawn darker the
// deeper they are and filled a little when they hold elements. Call it before drawing the objects.
package quadtree_kit

import qt ".."
import kit "../../demo_kit"

// One leaf: an outline that is darker the deeper the leaf is, a blue fill that grows with the number of elements
DrawLeaf :: proc(ctx: ^kit.Context, rect: kit.Rect, depth: int, count: int) {
    shade: u8 = u8(clamp(200 - depth * 18, 0, 200))
    if count > 0 { kit.DrawRect(ctx, rect, kit.Color{90, 140, 230, u8(min(20 + count * 8, 90))}) }
    kit.DrawRectOutline(ctx, rect, 1, kit.Color{shade, shade, shade, 255})
}

DrawQuadtree :: proc(ctx: ^kit.Context, tree: ^qt.Quadtree($E, $N, $L)) {
    qt.QuadtreeVisit(tree, ctx, drawNode)
}

DrawQuadtreeRetained :: proc(ctx: ^kit.Context, tree: ^qt.QuadtreeRetained($E, $N, $L)) {
    qt.QuadtreeRetainedVisit(tree, ctx, drawNode)
}

// The chunked world: every loaded chunk's tree, and the borders of the chunks when `borders` is set. `center` is the world position that is drawn at `screen_center` (the camera, the subtraction is done in
// f64 before the number gets small, so it works millions of units from the origin), one world unit is one pixel
DrawQuadtreeChunks :: proc(ctx: ^kit.Context, world: ^qt.QuadtreeChunks($W, $H, $E, $N, $L), center: qt.WorldVec, screen_center: kit.Vec2, borders: bool = true) {
    view: View = {ctx = ctx, center = center, screen_center = screen_center}
    qt.QuadtreeChunksVisit(world, &view, drawChunkNode)
    if !borders { return }
    for &chunk in world.chunks {
        if !chunk.loaded { continue }
        kit.DrawRectOutline(ctx, screenRect(&view, qt.QuadtreeChunksBounds(world, chunk.cx, chunk.cy)), 2, kit.Color{80, 120, 220, 255})
    }
}

// ------------------------------------------------------------------------------------------------------------------------

@(private)
View :: struct {
    ctx: ^kit.Context,
    center: qt.WorldVec,
    screen_center: kit.Vec2,
}

@(private)
screenRect :: proc(view: ^View, rect: qt.WorldRect) -> kit.Rect {
    return {f32(rect.x - view.center.x) + view.screen_center.x, f32(rect.y - view.center.y) + view.screen_center.y, f32(rect.w), f32(rect.h)}
}

@(private)
drawNode :: proc(user: rawptr, rect: qt.Rect, depth: int, leaf: bool, count: int) {
    if !leaf { return }
    DrawLeaf(cast(^kit.Context)user, transmute(kit.Rect)rect, depth, count)
}

@(private)
drawChunkNode :: proc(user: rawptr, rect: qt.WorldRect, depth: int, leaf: bool, count: int) {
    if !leaf { return }
    view: ^View = cast(^View)user
    DrawLeaf(view.ctx, screenRect(view, rect), depth, count)
}
