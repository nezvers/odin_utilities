package quadtree

import "core:container/handle_map"

Handle :: handle_map.Handle32

QuadNode :: struct {
    handle: Handle,
    aabb: AABB,
    branches: []QuadNode,
    leaves: []QuadNode,
}