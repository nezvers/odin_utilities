// Uniform grid broad phase and simple AABB narrow phase for 2D collisions, without allocations.
// Colliders live in a static handle map (stable Handle for each collider),
// every grid cell holds a fixed capacity list of collider Handles that touch the cell.
package grid_collision_map

import "core:math"
import hm "core:container/handle_map"

Handle :: hm.Handle32
HandleNone :Handle: {}

Vec2 :: [2]f32
vec2i :: [2]i32

// x, y = top left corner
Rect :: struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
}

// Axis aligned bounding box for an object
Collider :: struct {
    handle: Handle, // Required by handle map, set on GridMapAdd
    rect: Rect,
    ptr: rawptr,    // Generic way to carry user facing data
    cell_min: vec2i, // Runtime: grid cells occupied by the collider
    cell_max: vec2i,
}

// Holds Handles of all colliders occupying a grid cell
Slot :: struct($N: uint) {
    handles: [dynamic; N]Handle,
}

// X = columns, Y = rows, N = Handles per cell, C = colliders count (usable capacity is C - 1)
// Colliders outside of the grid are clamped into the border cells
GridMap :: struct($X: uint, $Y: uint, $N: uint, $C: uint) {
    position: Vec2,     // World position of the top left corner
    cell_size: Vec2,
    colliders: hm.Static_Handle_Map(C, Collider, Handle),
    slots: [X * Y]Slot(N),
}

MoveResult :: struct {
    rect: Rect,     // Collider rect after movement
    hit_x: bool,
    hit_y: bool,
}

// Set grid placement and remove all colliders
GridMapInit :: proc(grid: ^GridMap($X, $Y, $N, $C), position: Vec2, cell_size: Vec2) {
    assert(cell_size.x > 0 && cell_size.y > 0)
    GridMapClear(grid)
    grid.position = position
    grid.cell_size = cell_size
}

// Remove all colliders, handles become invalid
GridMapClear :: proc(grid: ^GridMap($X, $Y, $N, $C)) {
    hm.clear(&grid.colliders)
    for i: int = 0; i < len(grid.slots); i += 1 {
        clear(&grid.slots[i].handles)
    }
}

// World rectangle of the whole grid
GridMapRect :: proc(grid: ^GridMap($X, $Y, $N, $C)) -> Rect {
    return {grid.position.x, grid.position.y, cast(f32)X * grid.cell_size.x, cast(f32)Y * grid.cell_size.y}
}

// Cell coordinates covered by the rect, clamped to the grid. Touching a cell border doesn't count as covering the next cell
GridMapCellRange :: proc(grid: ^GridMap($X, $Y, $N, $C), rect: Rect) -> (cell_min: vec2i, cell_max: vec2i) {
    left: f32 = (rect.x - grid.position.x) / grid.cell_size.x
    top: f32 = (rect.y - grid.position.y) / grid.cell_size.y
    right: f32 = (rect.x + rect.w - grid.position.x) / grid.cell_size.x
    bottom: f32 = (rect.y + rect.h - grid.position.y) / grid.cell_size.y

    cell_min = {cast(i32)math.floor(left), cast(i32)math.floor(top)}
    cell_max = {cast(i32)math.ceil(right) - 1, cast(i32)math.ceil(bottom) - 1}
    cell_max.x = max(cell_max.x, cell_min.x)
    cell_max.y = max(cell_max.y, cell_min.y)

    cell_min.x = clamp(cell_min.x, 0, cast(i32)X - 1)
    cell_min.y = clamp(cell_min.y, 0, cast(i32)Y - 1)
    cell_max.x = clamp(cell_max.x, 0, cast(i32)X - 1)
    cell_max.y = clamp(cell_max.y, 0, cast(i32)Y - 1)
    return
}

// Add collider. Fails when collider or a cell is full, nothing is changed in that case
GridMapAdd :: proc(grid: ^GridMap($X, $Y, $N, $C), rect: Rect, ptr: rawptr = nil) -> (handle: Handle, ok: bool) {
    collider: Collider = {rect = rect, ptr = ptr}
    collider.cell_min, collider.cell_max = GridMapCellRange(grid, rect)
    if !SlotsHasSpace(grid, collider.cell_min, collider.cell_max, HandleNone) {
        return
    }

    handle, ok = hm.add(&grid.colliders, collider)
    if !ok {
        return
    }
    SlotsInsert(grid, handle, collider.cell_min, collider.cell_max)
    return
}

// Returns false when handle is not valid
GridMapRemove :: proc(grid: ^GridMap($X, $Y, $N, $C), handle: Handle) -> bool {
    collider: ^Collider = hm.get(&grid.colliders, handle) or_return
    SlotsRemove(grid, handle, collider.cell_min, collider.cell_max)
    return hm.remove(&grid.colliders, handle)
}

GridMapGet :: proc(grid: ^GridMap($X, $Y, $N, $C), handle: Handle) -> (collider: ^Collider, ok: bool) {
    return hm.get(&grid.colliders, handle)
}

GridMapLen :: proc(grid: ^GridMap($X, $Y, $N, $C)) -> uint {
    return hm.len(grid.colliders)
}

// Change collider rect and update occupied cells. Fails when new cells are full, collider is not changed in that case.
// Use it for teleporting, for moving with collision use GridMapMoveAndSlide
GridMapMove :: proc(grid: ^GridMap($X, $Y, $N, $C), handle: Handle, rect: Rect) -> bool {
    collider: ^Collider = hm.get(&grid.colliders, handle) or_return
    cell_min, cell_max: = GridMapCellRange(grid, rect)
    if cell_min == collider.cell_min && cell_max == collider.cell_max {
        collider.rect = rect
        return true
    }

    // Cells that collider already occupies don't need a free space
    if !SlotsHasSpace(grid, cell_min, cell_max, handle) {
        return false
    }
    SlotsRemove(grid, handle, collider.cell_min, collider.cell_max)
    SlotsInsert(grid, handle, cell_min, cell_max)
    collider.rect = rect
    collider.cell_min = cell_min
    collider.cell_max = cell_max
    return true
}

// Broad phase. Writes unique Handles of colliders that share cells with rect, doesn't check actual overlap.
// Returns count, extra colliders that don't fit into out are skipped
GridMapQueryBroad :: proc(grid: ^GridMap($X, $Y, $N, $C), rect: Rect, out: []Handle, ignore: Handle = HandleNone) -> (count: int) {
    cell_min, cell_max: = GridMapCellRange(grid, rect)
    for y: i32 = cell_min.y; y <= cell_max.y; y += 1 {
        for x: i32 = cell_min.x; x <= cell_max.x; x += 1 {
            slot: ^Slot(N) = &grid.slots[cast(int)x + cast(int)y * cast(int)X]
            for handle in slot.handles {
                if handle == ignore { continue }
                if count >= len(out) { return }
                if HandlesContain(out[:count], handle) { continue }
                out[count] = handle
                count += 1
            }
        }
    }
    return
}

// Broad phase followed by narrow phase. Writes Handles of colliders that overlap the rect
GridMapQuery :: proc(grid: ^GridMap($X, $Y, $N, $C), rect: Rect, out: []Handle, ignore: Handle = HandleNone) -> (count: int) {
    candidates: int = GridMapQueryBroad(grid, rect, out, ignore)
    for i: int = 0; i < candidates; i += 1 {
        collider: ^Collider = hm.get(&grid.colliders, out[i]) or_continue
        if !RectOverlaps(rect, collider.rect) { continue }
        out[count] = out[i]
        count += 1
    }
    return
}

// Move collider by delta and stop on other colliders, axes are resolved separately so collider slides along walls.
// Long movement is split in steps smaller than half a cell to not tunnel through thin colliders.
// buffer holds query results, it limits how many colliders are checked at once
GridMapMoveAndSlide :: proc(grid: ^GridMap($X, $Y, $N, $C), handle: Handle, delta: Vec2, buffer: []Handle) -> (result: MoveResult, ok: bool) {
    collider: ^Collider = hm.get(&grid.colliders, handle) or_return
    rect: Rect = collider.rect

    step_limit: f32 = min(grid.cell_size.x, grid.cell_size.y) * 0.5
    longest: f32 = max(abs(delta.x), abs(delta.y))
    steps: int = 1
    if longest > step_limit {
        steps = cast(int)math.ceil(longest / step_limit)
    }
    step: Vec2 = delta / cast(f32)steps

    for _ in 0..<steps {
        if step.x != 0 {
            rect.x += step.x
            if ResolveAxis(grid, &rect, handle, step.x, true, buffer) {
                result.hit_x = true
            }
        }
        if step.y != 0 {
            rect.y += step.y
            if ResolveAxis(grid, &rect, handle, step.y, false, buffer) {
                result.hit_y = true
            }
        }
    }

    result.rect = rect
    // Fails when new cells are full, collider stays at the previous position
    ok = GridMapMove(grid, handle, rect)
    if !ok {
        result.rect = collider.rect
    }
    return
}

// Narrow phase. Touching edges are not overlapping
RectOverlaps :: proc(a: Rect, b: Rect) -> bool {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

RectContainsPoint :: proc(rect: Rect, point: Vec2) -> bool {
    return point.x >= rect.x && point.x < rect.x + rect.w && point.y >= rect.y && point.y < rect.y + rect.h
}

// Smallest translation that moves `a` out of `b`
RectPushOut :: proc(a: Rect, b: Rect) -> (push: Vec2, hit: bool) {
    overlap_x: f32 = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
    overlap_y: f32 = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
    if overlap_x <= 0 || overlap_y <= 0 {
        return
    }
    hit = true
    if overlap_x < overlap_y {
        push.x = a.x + a.w * 0.5 < b.x + b.w * 0.5 ? -overlap_x : overlap_x
    } else {
        push.y = a.y + a.h * 0.5 < b.y + b.h * 0.5 ? -overlap_y : overlap_y
    }
    return
}

@(private="file")
HandlesContain :: proc(list: []Handle, handle: Handle) -> bool {
    for item in list {
        if item == handle { return true }
    }
    return false
}

// Push rect out of overlapping colliders along one axis, direction is taken from the movement
@(private="file")
ResolveAxis :: proc(grid: ^GridMap($X, $Y, $N, $C), rect: ^Rect, handle: Handle, step: f32, is_x: bool, buffer: []Handle) -> (hit: bool) {
    count: int = GridMapQuery(grid, rect^, buffer, handle)
    for i: int = 0; i < count; i += 1 {
        other: ^Collider = hm.get(&grid.colliders, buffer[i]) or_continue
        // Previous push could already move the rect away
        if !RectOverlaps(rect^, other.rect) { continue }

        hit = true
        if is_x {
            rect.x = step > 0 ? other.rect.x - rect.w : other.rect.x + other.rect.w
        } else {
            rect.y = step > 0 ? other.rect.y - rect.h : other.rect.y + other.rect.h
        }
    }
    return
}

// Cells where handle is already stored don't need space
@(private="file")
SlotsHasSpace :: proc(grid: ^GridMap($X, $Y, $N, $C), cell_min: vec2i, cell_max: vec2i, handle: Handle) -> bool {
    for y: i32 = cell_min.y; y <= cell_max.y; y += 1 {
        for x: i32 = cell_min.x; x <= cell_max.x; x += 1 {
            slot: ^Slot(N) = &grid.slots[cast(int)x + cast(int)y * cast(int)X]
            if len(slot.handles) < cap(slot.handles) { continue }
            if handle != HandleNone && HandlesContain(slot.handles[:], handle) { continue }
            return false
        }
    }
    return true
}

@(private="file")
SlotsInsert :: proc(grid: ^GridMap($X, $Y, $N, $C), handle: Handle, cell_min: vec2i, cell_max: vec2i) {
    for y: i32 = cell_min.y; y <= cell_max.y; y += 1 {
        for x: i32 = cell_min.x; x <= cell_max.x; x += 1 {
            slot: ^Slot(N) = &grid.slots[cast(int)x + cast(int)y * cast(int)X]
            append(&slot.handles, handle)
        }
    }
}

@(private="file")
SlotsRemove :: proc(grid: ^GridMap($X, $Y, $N, $C), handle: Handle, cell_min: vec2i, cell_max: vec2i) {
    for y: i32 = cell_min.y; y <= cell_max.y; y += 1 {
        for x: i32 = cell_min.x; x <= cell_max.x; x += 1 {
            slot: ^Slot(N) = &grid.slots[cast(int)x + cast(int)y * cast(int)X]
            for i: int = 0; i < len(slot.handles); i += 1 {
                if slot.handles[i] == handle {
                    unordered_remove(&slot.handles, i)
                    break
                }
            }
        }
    }
}
