# Fonts

- `FiraCode-Regular.ttf` + `FiraCode_OFL.txt` (SIL Open Font License 1.1): the font of every demo that draws through `demo_kit` (the raylib and the Karl2D backend load it when they start, so text
  that asks for no font gets it, the ui demos included). Taken from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/firacode) (`FiraCode[wght].ttf`, a variable font whose default
  is Light) and made static at weight 400 with `fontTools.varLib.instancer FiraCode.ttf wght=400 --update-name-table`, because stb_truetype and raylib read the default instance only.
- `font.ttf`, `pixellocale-v-1-4.ttf`: used by the atlas packer, localization and web build demos.

The stored screenshots of `ui` and `reports` (`captures/`) are made with Fira Code.
