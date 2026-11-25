package demo_common

// The demos of this library, written once against the demo kit (odin_utilities/demo_kit): shapes, text and input through `kit.Context`.
// demo_raylib and demo_karl2d only start them on their framework, demo_common_test.odin plays their scripts headless.

import kit "../../demo_kit"

demos: []kit.Demo = {demo_rebind, demo_gallery, demo_examples, demo_widgets, demo_layout, demo_styles, demo_navigation, demo_imgui, demo_resize, demo_graph, demo_audio, demo_scale, demo_text, demo_timeline, demo_table, demo_inspector, demo_tree, demo_dock, demo_color, demo_combo, demo_shell, demo_emoji, demo_windows, demo_smooth, demo_nota, demo_editors, demo_chain, demo_pads, demo_modulation, demo_history, demo_styleeditor}
