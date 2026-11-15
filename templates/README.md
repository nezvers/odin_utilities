# Templates

Copy a template into a new project folder, next to the libraries it imports (the relative imports are written for that layout).

To build the templates here, in place, two directory junctions are needed (they are git ignored, create them once per clone):

```bat
mklink /J templates\karl2d <absolute path of odin_utilities\karl2d>
mklink /J templates\viewport_rect <absolute path of odin_utilities\viewport_rect>
```

`library/` is the skeleton of an odin_utilities library (core, glue, tests, `demo_common`, both demos), see its README. It imports `../../demo_kit` and `../../karl2d`, so it needs a third junction:

```bat
mklink /J templates\demo_kit <absolute path of odin_utilities\demo_kit>
```
