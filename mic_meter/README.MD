# Mic peak meter
MiniAudio based mic peak metter.    
Usable for user microphone volume as an app input.    
`odin run demo_raylib`    
For Linux first time using MiniAudio, Odin will suggest to compile MiniAudio in the vendors directory.

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demos from `demo_common`, written once against the
demo kit (`odin_utilities/demo_kit`). Each demo has a script of simulated input with checks:
`odin test demo_common -strict-style -vet` plays it headless, `odin run demo_raylib -define:DEMO_TEST=true` plays it in the window.

There is no `demo_raylib`: the static raylib library contains its own copy of miniaudio (raudio), and linking it with `vendor:miniaudio` fails with "symbol ma_version is multiply defined". The demo runs with Karl2D only.
