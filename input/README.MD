# Input
Helper functions to implement input rebinding or reading axis inputs as button state (pressed, released, held).    
`odin run demo`    
    
`UpdateAxis()` - call at update loop beginning to enable axis as button states    
`GetAxisState(device: i32, id: i32)` - used internally but can be used to read if axis is in either polarity end    
`ListenRebind()` - listen when any of inputs are in just released state    
`IsPressed(input_id: InputID)` - check if input is just pressed    
`IsReleased(input_id: InputID)` - check if input is just released    
`IsDown(input_id: InputID)` - check if input is held down    