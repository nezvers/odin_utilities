# Sound Effects
`odin run demo_raylib`
- Handle retrigger timing. No overlapping sounds at the same time making sound louder.    
- Randomize pitch to make same sound non-robotic    
- Pitch go up on repeated trigger    

###### Karl2D
`odin run demo_karl2d`

###### Effects as data
`SoundSettings` (constant tuning) and `SoundState` (pitch, last trigger time) are separate. A `SoundBank` holds a settings slice and a states slice (yours, e.g. in game memory) and an effect is a `SoundId` index, so prefabs hold ids and not pointers. `SoundBankRebind` after a hot reload keeps the states. Glue: `PlayBank`. Tests: `odin test sound_effects`.
