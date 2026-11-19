package demo_common

// The demos of this library, written once against the demo kit (odin_utilities/demo_kit). The text itself is drawn by the glue of a framework (a TextDrawer that demo_raylib and demo_karl2d set
// before they run the demos), everything else by the kit. demo_common_test.odin plays their scripts headless, where the text is not drawn.

import kit "../../demo_kit"

demos: []kit.Demo = {demo_font, demo_rich}
