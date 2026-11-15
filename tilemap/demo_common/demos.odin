package demo_common

// The demos of this library, written once against the demo kit: demo_raylib and demo_karl2d only start them on their framework,
// demo_common_test.odin plays their scripts headless.

import kit "../../demo_kit"

demos: []kit.Demo = {demo_atlas, demo_tile, demo_tileset, demo_tilemap, demo_grid, demo_region, demo_paint, demo_drag, demo_resize, demo_ruletile, demo_dualgrid}
