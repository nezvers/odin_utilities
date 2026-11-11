# FPS Controller

Just demo example how to create camera rotation, animation ideas, boomer shooter velocity.    
No actual physics in the first state, just movement.    

- Strafe jumping    
- Boomer shooter camera animations     
- Box3D state: same player with collision from `vendor:box3d`    

`odin run demo_raylib`    

## Files
- `player.odin` - movement, camera animation and input shared by both states.
- `controller.odin` - state `CONTROLLER`: flat floor, collision is a clamp to `y = 0`.
- `controller_box3d.odin` - state `BOX3D`: the player is a Box3D capsule mover. Every frame it gathers collision planes (`World_CollideMover`), solves them (`SolvePlanes`), casts the move (`World_CastMover`), clips velocity (`ClipVector`) and pushes dynamic bodies it touches. Static ground and towers, a wall of crates and shot spheres are simulated by the Box3D world. LMB shoots a sphere, `R` resets. Ported from the Box2D `GeometricMover` sample.
