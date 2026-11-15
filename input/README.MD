# Input
Helper functions to implement input rebinding and reading axis inputs as button state (pressed, released, held).    
`UpdateAxis()` - call at update loop beginning to enable axis as button states    
`GetAxisState(device: i32, id: i32)` - used internally but can be used to read if axis is in either polarity end    
`ListenRebind()` - listen when any of inputs are in just released state    
`IsPressed(input_id: InputID)` - check if input is just pressed    
`IsReleased(input_id: InputID)` - check if input is just released    
`IsDown(input_id: InputID)` - check if input is held down    
`GetValue(input_id: InputID)` - Read float value from inputs    
`GetValueAxis(negative: InputID, positive: InputID)` - Read float value for directions -1 to 1

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d`: input rebinding through the glue of the framework (`glue_raylib/`, `glue_karl2d/`), the demo itself is in `demo_common` and reaches the glue
through an `Adapter` (a table of procs the framework fills). raylib also has a gamepad state demo.
The glue reads the real devices, so simulated input cannot reach it: `odin test demo_common -strict-style -vet` and `-define:DEMO_TEST=true` run the demo script on an adapter over the keys of the demo kit
(`KitAdapter`), which plays the whole rebinding flow (click Rebind, press a key, the action follows it).
