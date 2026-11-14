# Templates

Copy a template into a new project folder, next to the libraries it imports (the relative imports are written for that layout).

To build the templates here, in place, two directory junctions are needed (they are git ignored, create them once per clone):

```bat
mklink /J templates\karl2d <absolute path of odin_utilities\karl2d>
mklink /J templates\viewport_rect <absolute path of odin_utilities\viewport_rect>
```
