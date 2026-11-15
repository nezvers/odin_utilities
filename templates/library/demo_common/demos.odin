package demo_common

// The demos of this library, written ONCE against the demo kit (odin_utilities/demo_kit): shapes, text, textures, sound and input
// through `kit.Context`. demo_raylib and demo_karl2d only start them on their framework, demo_common_test.odin plays their scripts
// headless. What needs a framework (a glue draw proc, 3D) goes to the demo folder of that framework, not here.

import kit "../../demo_kit"

demos: []kit.Demo = {demo_counter}
