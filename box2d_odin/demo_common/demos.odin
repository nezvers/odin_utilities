package demo_common

// The demos of this library, written once against the demo kit: demo_raylib and demo_karl2d only start them on their framework,
// demo_common_test.odin plays their scripts headless.

import kit "../../demo_kit"

// Filled by buildScript (demo_samples.odin): the script of the samples browser is made at start, so the list cannot be a constant
demos: [2]kit.Demo
