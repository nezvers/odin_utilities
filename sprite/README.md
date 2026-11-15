# Sprite
- Playing sequential rectangle sections from texture.
- frame rate, origin point, scale, rotation
`odin run demo_raylib`

### Karl2D
Karl2D need to be next to other libraries in this repository.
`odin run demo_karl2d`

### Sprites as data (`sheet.odin`)
`Sheet` (frame positions + clips) is a row of a constant table, `Animator` (sheet, clip, frame, time) refers to it by number, `SheetSprite` adds the transform. No pointers, so a sprite can be copied, put in prefab data, overridden by field and saved. `AnimatorUpdate` loops, `AnimatorUpdateOnce` stops on the last frame (effects). Draw with `DrawSheetSprite(sheets, sprite, texture, tint)` from the glue packages. Tests: `odin test sprite`.
