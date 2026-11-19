package icons

// Icons as a font. The pictures are the Lucide set (https://lucide.dev, ISC License; some come from Feather, MIT License: icons/lucide/LICENSE), each one a glyph of
// `lucide.ttf`, which icons/tool/build makes from the sprite sheet: an icon is drawn like a letter, by whatever draws text (a framework's font, a glyph atlas,
// odin_utilities/font, atlas_packer), in any size and color, and it sits in the same batch as the text around it.
//
//     font := load the bytes of icons.LUCIDE_FONT with the framework
//     text := icons.IconText(.FOLDER_OPEN)             // the icon as a string of one character
//     draw text with that font at a size: the picture fills the square of that size
//
// The enum of the icons (`Icon`) and their names are in lucide_icons.odin, which the tool writes. The rest of the package is what the tool is made of and can be used for
// other sets: SvgPathParse (path data), StrokePath / FillPath (lines of a width as filled outlines), FontWrite (outlines as a TrueType file).

import "core:unicode/utf8"

// The font file. It is part of a program only when the program names this.
LUCIDE_FONT :: #load("lucide.ttf")

// The first icon is this character (the start of the private use area of Unicode), the others follow in the order of the enum
ICON_FIRST_CHARACTER :: rune(0xE000)

// The font: the box of an icon (24 by 24 in the sprite) is the em. The baseline is a bit above the bottom of the box, so that an icon in a line of text stands around the
// middle of the capital letters; drawn alone, the box is `ICON_ASCENT / ICON_UNITS_PER_EM` of the size above the baseline and the rest below.
ICON_GRID :: f32(24)
ICON_UNITS_PER_EM :: 2400
ICON_ASCENT :: 2040
ICON_DESCENT :: -360

// The character of an icon, 0 for NONE
IconRune :: proc "contextless" (icon: Icon) -> rune {
    if icon == .NONE { return 0 }
    return ICON_FIRST_CHARACTER + rune(icon) - 1
}

// An icon as text of one character. The bytes are in the value that is returned: keep it in a variable and take `IconString` of that.
IconText :: proc "contextless" (icon: Icon) -> (text: [4]u8, length: int) {
    if icon == .NONE { return }
    return utf8.encode_rune(IconRune(icon))
}

// The string of what IconText gave (it points into `text`)
IconString :: proc "contextless" (text: ^[4]u8, length: int) -> string {
    return string(text[:length])
}

// The icon with a name of the list ("folder-open"), NONE when there is none
IconFromName :: proc(name: string) -> Icon {
    for icon_name, icon in ICON_NAMES {
        if icon != .NONE && icon_name == name { return icon }
    }
    return .NONE
}
