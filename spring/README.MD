# Spring
Functions for procedural animations to give secondary motion (boyancy, jiggle, springiness)    
Included also multiple 3rd party solutions (linked to sources), but I need help to make them work as demo showcase.
    
`odin run demo_raylib`

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demos from `demo_common`, written once against the
demo kit (`odin_utilities/demo_kit`). Each demo has a script of simulated input with checks:
`odin test demo_common -strict-style -vet` plays it headless, `odin run demo_raylib -define:DEMO_TEST=true` plays it in the window.
