# Fonts

- `font.ttf`, `pixellocale-v-1-4.ttf`: used by the atlas packer, localization and web build demos.
- `JetBrainsSans-Regular.ttf` (not in the repository, kept out of git on purpose: the font file says "Copyright (c) 2020 by Philipp Nurullin. All rights reserved" and no
  license was found; it was made from the WOFF that JetBrains serves at `resources.jetbrains.com/storage/jetbrains-sans/`). The demos of `ui` and `reports` use it when the file is there
  (`#exists` at compile time) and the font of the framework otherwise. The stored screenshots (`captures/`) were made with it: without the file `odin run demo_kit/tool/captures`
  reports every picture as changed, and a script that clicks at fixed coordinates may miss (headless runs use a fixed width font, so the scripts click where both fit).
