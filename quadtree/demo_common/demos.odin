package demo_common

// The demos of this library, written once against the demo kit: demo_raylib and demo_karl2d only start them on their framework,
// demo_common_test.odin plays their scripts headless.

import kit "../../demo_kit"

demos: []kit.Demo = {demo_collision, demo_hover, demo_balls, demo_retained}
