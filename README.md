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

- ✅ 3D models (glTF/GLB, skinning, raylib) `odin run 3d_models/demo_raylib`
- ✅ [App state][app_state] `odin run app_state/demo_raylib`
- ❎ Astar `odin run astar/demo_raylib`
    - ✅ grid 2D (4-way Manhattan, 8-way Euclidian)
- ✅ [Atlas Packer][atlas_packer] `odin run atlas_packer/demo_raylib -out:atlas_packer/demo.exe`
- ✅ Box2d Odin `odin run box2d_odin/demo_raylib`
- ❎ Cool math `odin run cool_math/demo_raylib`
- ✅ Drag'n'Drop `odin run drag_drop/demo_raylib`
- ✅ FABRIK IK `odin run fabrik/demo_raylib`
- ✅ [FPS Controller][fps_controller] `odin run fps_controller/demo_raylib -out:fps_controller/demo.exe`
- ❎ Geometry2D `odin run geometry2d/demo_raylib`
    - ✅ shapes [point, line, circle, rectangle, triangle, ray]
    - ✅ overlap
    - ✅ contains
    - ✅ intersect
    - ❎ closest
    - ❎ project
    - ❎ envelope
- ✅ [Input][input] `odin run input/demo_raylib`
- ✅ Localization `odin run localization/demo_raylib -out:localization/demo.exe`
- ✅ MicMeter `odin run mic_meter/demo_raylib`
- ✅ Microui (raylib, karl2d) `odin run microui/demo_raylib`
- ✅ Particles `odin run particles/demo_raylib -out:particles/demo.exe`
- ✅ [Save file][save_file] `odin run save_file/demo_raylib`
- ✅ Sound Effect `odin run sound_effects/demo_raylib -out:sound_effects/demo.exe`
- ✅ Spring `odin run spring/demo_raylib`
- ✅ Sprite `odin run sprite/demo_raylib -out:sprite/demo.exe`
- ✅ [Task][task] `odin run task/demo_raylib -out:task/demo.exe`
    - Call process with arguments
    - Download file
    - Extract TAR & ZIP
    - Clone git repository
- ✅ [Tilemap][tilemap] `odin run tilemap/demo_raylib -out:tilemap/demo.exe`
- ✅ Timer `odin run timer/demo_raylib -out:timer/demo.exe`
- ✅ Viewport Rect `odin run viewport_rect/demo_raylib`
