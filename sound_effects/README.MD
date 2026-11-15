# Sound Effects
`odin run demo_raylib`
- Handle retrigger timing. No overlapping sounds at the same time making sound louder.    
- Randomize pitch to make same sound non-robotic    
- Pitch go up on repeated trigger    

###### Karl2D
`odin run demo_karl2d`

###### Effects as data
`SoundSettings` (constant tuning) and `SoundState` (pitch, last trigger time) are separate. A `SoundBank` holds a settings slice and a states slice (yours, e.g. in game memory) and an effect is a `SoundId` index, so prefabs hold ids and not pointers. `SoundBankRebind` after a hot reload keeps the states. Glue: `PlayBank`. Tests: `odin test sound_effects`.

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demos from `demo_common`, written once against the
demo kit (`odin_utilities/demo_kit`). Each demo has a script of simulated input with checks:
`odin test demo_common -strict-style -vet` plays it headless, `odin run demo_raylib -define:DEMO_TEST=true` plays it in the window.
