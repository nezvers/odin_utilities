# unicode_data: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `unicode_data.odin` (`RuneWidth` 0, 1, 2, `RuneAmbiguous`, `RuneEmojiText`, `ClusterWidth`, `RuneGraphemeClass`, `GraphemeBreak` with a `GraphemeState`: UAX #29 of Unicode 18), `tables.odin` (GENERATED: `odin run unicode_data/tool/gen -- <folder of the UCD files> unicode_data/tables.odin`; the UCD files are not in the repository, `references/ucd` holds a copy), `testdata/GraphemeBreakTest.txt` (the official test, run by the tests). Used by `ui/ansi_screen.odin`; the width of a character anywhere in odin_utilities comes from here, never from a hand written table.
