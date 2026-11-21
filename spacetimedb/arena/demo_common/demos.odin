#+build !js
package demo_common

// The demo of this example, written once against the demo kit: demo_raylib and demo_karl2d start it on their framework, demo_common_test.odin plays its script headless against a real server.

import kit "../../../demo_kit"

demos: []kit.Demo = {demo_arena}
