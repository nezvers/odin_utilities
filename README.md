# odin_utilities
 Collection of Odin utility libraries for game and app development.    
 Libraries are bite sized and data only and avoiding allocations if possible.    
 Each one comes with demo example and if needed glue code at least for Raylib.    

[app_state]: ## "Simple showcase how to manage multi state application. Uses struct with callback functions."
[atlas_packer]: ## "Runtime 2D asset packing"
[save_file]: ## "Simple save file system to store structs as POD or byte array"
[task]: ## "Functionality for system automatization, like custom project build system. Clone, extract archive, download files, call processes"
[tilemap]: ## "Purely data driven Tile map system, with capability and demo to create in-game level editors."
[fps_controller]: ## "Camera rotation, camera animation, strafe jump velocity"
[input]: ## "Helper functions for rebinding and gamepad axis as buttons functionality"

- ✅ [App state][app_state] `odin run app_state/demo`
- ❎ Astar `odin run astar/demo`
    - ✅ grid 2D (4-way Manhattan, 8-way Euclidian)
- ✅ [Atlas Packer][atlas_packer] `odin run atlas_packer/demo -out:atlas_packer/demo.exe`
- ✅ Box2d Odin `odin run box2d_odin/demo`
- ❎ Cool math `odin run cool_math/demo`
- ✅ Drag'n'Drop `odin run drag_drop/demo`
- ✅ FABRIK IK `odin run fabrik/demo`
- ✅ [FPS Controller][fps_controller] `odin run fps_controller/demo -out:fps_controller/demo.exe`
- ❎ Geometry2D `odin run geometry2d/demo`
    - ✅ shapes [point, line, circle, rectangle, triangle, ray]
    - ✅ overlap
    - ✅ contains
    - ✅ intersect
    - ❎ closest
    - ❎ project
    - ❎ envelope
- ✅ [Input][input] `odin run input/demo`
- ✅ Localization `odin run localization/demo -out:localization/demo.exe`
- ✅ MicMeter `odin run mic_meter/demo`
- ✅ Microui (raylib) `odin run microui/demo`
- ✅ Particles `odin run particles/demo -out:particles/demo.exe`
- ✅ [Save file][save_file] `odin run save_file/demo`
- ✅ Sound Effect `odin run sound_effects/demo -out:sound_effects/demo.exe`
- ✅ Spring `odin run spring/demo`
- ✅ Sprite `odin run sprite/demo -out:sprite/demo.exe`
- ✅ [Task][task] `odin run task/demo -out:task/demo.exe`
    - Call process with arguments
    - Download file
    - Extract TAR & ZIP
    - Clone git repository
- ✅ [Tilemap][tilemap] `odin run tilemap/demo -out:tilemap/demo.exe`
- ✅ Timer `odin run timer/demo -out:timer/demo.exe`
- ✅ Viewport Rect `odin run viewport_rect/demo`
