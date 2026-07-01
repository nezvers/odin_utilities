package grid_collision_map

import hm "core:container/handle_map"
Handle :: hm.Handle32

Vec2 :: [2]f32
Rect :: [4]f32

// Bounding box for an object
Box :: struct {
    rect: Rect,
    ptr: rawptr,
}

// Buffer holds all boxes occupying grid slot
Slot :: struct($N:uint) {
    handle: Handle,
    buffer: [dynamic; N]Box,
}

// X = Columns, Y = ROWS, N = Slot cap
GridMap :: struct($X: uint, $Y:uint, $N:uint) {
    handle_buffer: hm.Static_Handle_Map((X*Y), Slot(N), Handle),
}