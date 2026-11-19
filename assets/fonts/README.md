# Fonts

- `FiraCode-Regular.ttf` + `FiraCode_OFL.txt` (SIL Open Font License 1.1): the font of every demo that draws through `demo_kit` (the raylib and the Karl2D backend load it when they start, so text
  that asks for no font gets it, the ui demos included). Taken from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/firacode) (`FiraCode[wght].ttf`, a variable font whose default
  is Light) and made static at weight 400 with `fontTools.varLib.instancer FiraCode.ttf wght=400 --update-name-table`, because stb_truetype and raylib read the default instance only.
- `font.ttf`, `pixellocale-v-1-4.ttf`: used by the atlas packer, localization and web build demos.
- `inter/Inter-Regular.ttf`, `-Medium`, `-SemiBold`, `-Bold`, `-Italic` + `inter/Inter-OFL.txt` (SIL Open Font License 1.1, Copyright (c) 2016 The Inter Project Authors, https://github.com/rsms/inter):
  the typeface of the ui. Static instances of `InterVariable.ttf` and `InterVariable-Italic.ttf` (taken from the Baldr repository, which ships the variable files of Inter 4) at the optical size 14
  and the weights 400, 500, 600, 700, made with `python -m fontTools.varLib.instancer InterVariable.ttf wght=500 opsz=14 --update-name-table -o Inter-Medium.ttf`, because the parser of the font
  library, stb_truetype and raylib read the default instance of a variable font only. A program that ships a font ships its license text with it.
- `jetbrains_mono/`: JetBrains Mono (OFL), the code face.
- The icon font is not here: `icons/lucide.ttf` is built by the icons library (Lucide, ISC License).

The stored screenshots of `ui` and `reports` (`captures/`) are made with Fira Code.
