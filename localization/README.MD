# Localization
- Translation CSV with most used game texts
- Load CSV with translation data    

`odin run demo_raylib` / `odin run demo_karl2d`

Karl2D demo uses a dynamic font, so characters of every language in the CSV are added to the font atlas when they are drawn.

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demos from `demo_common`, written once against the
demo kit (`odin_utilities/demo_kit`). Each demo has a script of simulated input with checks:
`odin test demo_common -strict-style -vet` plays it headless, `odin run demo_raylib -define:DEMO_TEST=true` plays it in the window.
