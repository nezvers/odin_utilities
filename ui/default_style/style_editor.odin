package ui_default

// A style editor for the default style, small enough to ship inside of an application: a floating window that edits a `Theme` (every field of it, found by reflection: a field that is added to Theme
// is editable at once), picks elements of the running ui to edit the fields they are drawn with (edit mode, ui/edit.odin: the element under the pointer is covered by a light veil, a press
// picks it), and loads, saves and deletes styles through a `StyleStore` (style_store.odin: files, or whatever the application keeps its settings in). Nothing here knows about a framework or a file.
//
//     editor: ui_default.StyleEditor                                // keep it as long as the program runs
//     ui_default.StyleEditorInit(&editor, ui_default.THEME_DARK)
//     ...
//     // every frame, wherever the editor should be (a key or a menu says if it is open):
//     if open {
//         if ui_default.UiStyleEditor(&ctx, &editor, &store) { painter.theme = editor.theme }       // true in the frames the style changes
//     } else { ui.UiEditMode(&ctx, false) }
//
// What the style is used for is the program's: `editor.theme` is the style that is being edited and `editor.apply` is the switch of the window that says "show it", so a program that draws with
// its own look when it is off reads both. The edit mode, the cover over the hovered element and the colors of the covers (`edit_overlay`, `edit_selected`) are in the theme, so they are saved
// with the style and edited here like the rest.
//
// Limits: the fields of Theme only (a style of your own that has more reads and writes its own); the elements are told apart by what the style draws them as (their kind), so "the fields of a
// button" are all buttons'; a name of a style is plain letters, digits, space, dash and underscore (StyleNameValid).

import ui ".."

STYLE_EDITOR_TITLE :: "Style editor"

StyleEditor :: struct {
    theme: Theme,               // the style that is edited
    apply: bool,                // the window's switch: the program draws with `theme`
    pick: bool,                 // edit mode
    position: ui.Vec2,          // where the window is (it is dragged by its title)
    selected: int,              // the field that is edited
    name: [STYLE_NAME_LENGTH]u8,
    name_length: int,
    chosen: int,                // the entry of the list of styles
    names: StyleNames,
    listed: bool,               // `names` is up to date
    filter: [24]u8,
    filter_length: int,
    status: [80]u8,
    status_length: int,
    rgb: [3]f32,                // the working copy of a color field for the picker
    alpha: f32,
    fonts: SkinFonts,           // the font files of the skin (skin.odin): a field for each face
    fonts_serial: u32,          // changes when a font name does or a style with fonts is loaded: the program loads the fonts then
    show_fonts: bool,
}

StyleEditorInit :: proc(editor: ^StyleEditor, theme: Theme, position: ui.Vec2 = {40, 40}) {
    editor^ = {theme = theme, position = position, selected = ThemeFieldFind("accent")}
}

// The fields a kind of element is drawn with, by name of the kind (the others of the theme are shared: the text, the accent). The first ones are what the kind is mostly about.
@(private)
EDIT_FIELDS :: [?]struct {
    kind: ui.StyleKind,
    name: string,               // only for the elements of this name (the style draws a panel called "code" as a well, a "tooltip" as a raised card): "" for every element of the kind
    fields: string,
}{
    {.PANEL, "code", "track,border_soft,rounding,max_radius,border_width"},
    {.PANEL, "tooltip", "surface_high,border,panel_rounding,max_radius,border_width,shadow"},
    {.PANEL, "dropdown", "surface_high,border,panel_rounding,max_radius,border_width,shadow"},
    {.PANEL, "combo", "surface_high,border,panel_rounding,max_radius,border_width,shadow"},
    {.PANEL, "menu", "surface_high,border,panel_rounding,max_radius,border_width,shadow"},
    {.PANEL, "", "panel,border_soft,border,surface_high,panel_rounding,panel_max_radius,border_width,shadow"},
    {.LABEL, "", "text,text_dim,accent"},
    {.BUTTON, "", "control,control_hover,control_pressed,text,accent,accent_text,accent_soft,accent_soft_text,danger,danger_text,border,rounding,max_radius,border_width,hover,press,focus"},
    {.TOGGLE, "", "track,track_strong,accent,accent_text,border,text,rounding,max_radius,border_width,focus"},
    {.SWITCH, "", "track_strong,accent,accent_text,panel,focus"},
    {.RADIO, "", "track,accent,border,text,focus"},
    {.SLIDER, "", "track,accent_soft,accent,accent_text,border,text,rounding,max_radius,border_width,focus"},
    {.FREQ_GRAPH, "", "panel,track,border,text,text_dim,accent,accent_soft,success"},
    {.WAVEFORM, "", "panel,track,border,text,text_dim,accent,accent_soft,warning"},
    {.MIXER_FADER, "", "track,accent,accent_soft,border,text,text_dim,success,warning,danger,rounding,max_radius"},
    {.RANGE_SLIDER, "", "track,accent,accent_soft,border,text,text_dim,focus"},
    {.MOD_MATRIX, "", "track,accent,accent_soft,border,text,text_dim,warning,rounding,max_radius,border_width,focus"},
    {.OVERVIEW, "", "track,accent,accent_soft,border,text,text_dim,rounding,max_radius,border_width,focus"},
    {.XY_PAD, "", "track,accent,border,text,text_dim,rounding,max_radius,border_width,focus"},
    {.WHEEL, "", "track,accent,border,text_dim,rounding,max_radius,border_width,focus"},
    {.SCROLL_BAR_THIN, "", "track,text,text_dim"},
    {.KEYBOARD, "", "panel,border,text,accent,warning,focus"},
    {.STEP_GRID, "", "panel,track,border,accent,accent_soft,rounding,focus"},
    {.PIANO_ROLL, "", "panel,track,border,text,text_dim,accent,accent_soft,rounding"},
    {.VALUE_BAR, "", "track,accent_soft,accent,border,text,text_dim,rounding,max_radius,border_width,focus"},
    {.PROGRESS, "", "track,accent,accent_text,text,max_radius"},
    {.TEXT_FIELD, "", "track,border,accent,text,text_dim,rounding,max_radius,border_width,focus"},
    {.TEXT_AREA, "", "track,border,accent,text,text_dim,rounding,max_radius,border_width,focus"},
    {.DROPDOWN, "", "track,border,accent,text,rounding,max_radius,border_width,surface_high"},
    {.DROPDOWN_ITEM, "", "surface_high,accent_soft,accent_soft_text,text,control_hover"},
    {.SEPARATOR, "", "border_soft"},
    {.SCROLLBAR, "", "track,track_strong,control_hover"},
    {.TAB, "", "accent,text,text_dim,border_soft,control_hover"},
    {.SEGMENTED, "", "track,surface_high,text,text_dim,rounding,max_radius"},
    {.SEGMENT, "", "surface_high,text,text_dim,rounding,max_radius"},
    {.CHIP, "", "control,accent_soft,accent_soft_text,text,border,rounding"},
    {.BADGE, "", "accent_soft,accent_soft_text,danger,warning,success,text"},
    {.WINDOW_TITLE, "", "track,text,text_dim,panel_max_radius,border_width"},
    {.MENU_BAR, "", "panel,border_soft,text"},
    {.MENU, "", "surface_high,border,text,control_hover,max_radius"},
    {.MENU_ITEM, "", "surface_high,control_hover,text,text_dim,accent_soft"},
    {.COLLAPSING, "", "control,control_hover,text,accent"},
    {.SELECTABLE, "", "accent_soft,accent_soft_text,control_hover,text"},
    {.BACKDROP, "", "scrim"},
    {.GRAPH_NODE, "", "panel,border,accent,track,panel_rounding,max_radius,border_width,text"},
    {.GRAPH_PIN, "", "accent,track,text"},
    {.EDIT_COVER, "", "edit_overlay,edit_selected"},
}

// Whether a field is one of those the picked element is drawn with: the entry of its kind and its name when there is one, else the entry of the kind
@(private)
styleFieldUsed :: proc(kind: ui.StyleKind, name: string, element: string = "") -> bool {
    table := EDIT_FIELDS
    named: bool
    for entry in table {
        if entry.kind == kind && entry.name != "" && entry.name == element { named = true }
    }
    for entry in table {
        if entry.kind != kind { continue }
        if named ? entry.name != element : entry.name != "" { continue }
        rest: string = entry.fields
        for len(rest) > 0 {
            comma: int = -1
            for i in 0 ..< len(rest) {
                if rest[i] == ',' {
                    comma = i
                    break
                }
            }
            part: string = rest if comma < 0 else rest[:comma]
            if part == name { return true }
            rest = "" if comma < 0 else rest[comma + 1:]
        }
    }
    return false
}

@(private)
styleStatus :: proc(editor: ^StyleEditor, text: string) {
    editor.status_length = copy(editor.status[:], text)
}

// The range of a number field
@(private)
styleNumberRange :: proc(name: string) -> (low: f32, high: f32) {
    switch name {
    case "hover", "press": return 0, 0.5
    case "rounding", "panel_rounding": return 0, 1
    case "max_radius", "panel_max_radius": return 0, 40
    case "border_width": return 0, 6
    }
    return 0, 1
}

@(private)
styleFieldMatches :: proc(name: string, filter: string) -> bool {
    if len(filter) == 0 { return true }
    for start in 0 ..= len(name) - len(filter) {
        if name[start:start + len(filter)] == filter { return true }
    }
    return false
}

// The window. `store` nil: no saving and loading. True in the frames the theme changes (a field, a style that was loaded).
UiStyleEditor :: proc(ctx: ^ui.Context, editor: ^StyleEditor, store: ^StyleStore = nil) -> (changed: bool) {
    if store != nil && !editor.listed {
        store.list(store, &editor.names)
        editor.listed = true
    }
    // edit mode: the mask is on while the switch is, and the window is the panel the pointer works
    ui.UiEditMode(ctx, editor.pick, {}, ui.UiId(ctx, STYLE_EDITOR_TITLE))
    picked, was_picked := ui.UiEditPicked(ctx)

    if ui.UiWindowTitled(ctx, STYLE_EDITOR_TITLE, &editor.position, {ui.Fixed(360), {}}, {direction = .TOP_TO_BOTTOM, gap = 6, padding = ui.PaddingAll(10)}, 200) {
        ui.ElementOpen(ctx, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 12, align = {y = .CENTER}}})
        if ui.UiToggle(ctx, "Pick element", &editor.pick) && !editor.pick { ui.UiEditClear(ctx) }
        ui.UiToggle(ctx, "Apply", &editor.apply)
        ui.ElementClose(ctx)
        if was_picked && editor.pick {
            ui.UiLabelDim(ctx, ui.UiFormat(ctx, "picked: %v  %s", picked.kind, ui.EditTargetName(&picked)))
        } else {
            ui.UiLabelDim(ctx, "Pick element: point at the ui, press to choose")
        }
        if store != nil {
            options: [STYLE_NAMES]string
            for i in 0 ..< editor.names.count { options[i] = StyleNameAt(&editor.names, i) }
            ui.ElementOpen(ctx, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6, align = {y = .CENTER}}})
            if editor.names.count > 0 {
                editor.chosen = clamp(editor.chosen, 0, editor.names.count - 1)
                ui.UiDropdown(ctx, "##styles", options[:editor.names.count], &editor.chosen, {ui.Grow(), {}})
                if ui.UiButton(ctx, "Load") {
                    name: string = options[editor.chosen]
                    if store.load(store, name, &editor.theme) {
                        changed = true
                        if store.load_fonts != nil {
                            editor.fonts = {}
                            store.load_fonts(store, name, &editor.fonts)
                            editor.fonts_serial += 1
                        }
                        editor.name_length = copy(editor.name[:], name)
                        styleStatus(editor, ui.UiFormat(ctx, "loaded %s", name))
                    } else {
                        styleStatus(editor, "could not load it")
                    }
                }
            } else {
                ui.UiLabelDim(ctx, "no saved styles")
            }
            ui.ElementClose(ctx)
            ui.ElementOpen(ctx, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6, align = {y = .CENTER}}})
            ui.UiTextField(ctx, "##style_name", editor.name[:], &editor.name_length, {ui.Grow(), {}})
            name: string = string(editor.name[:editor.name_length])
            valid: bool = StyleNameValid(name)
            if ui.UiDisabled(ctx, !valid) {
                if ui.UiButton(ctx, "Save") {
                    if store.save(store, name, &editor.theme) {
                        if store.save_fonts != nil { store.save_fonts(store, name, &editor.fonts) }
                        editor.listed = false
                        styleStatus(editor, ui.UiFormat(ctx, "saved %s", name))
                    } else {
                        styleStatus(editor, "could not save it")
                    }
                }
                if ui.UiButton(ctx, "Delete", {}, false) {
                    if store.delete(store, name) {
                        editor.listed = false
                        styleStatus(editor, ui.UiFormat(ctx, "deleted %s", name))
                    } else {
                        styleStatus(editor, "there is no such style")
                    }
                }
            }
            ui.ElementClose(ctx)
            if editor.status_length > 0 { ui.UiLabelDim(ctx, string(editor.status[:editor.status_length])) }
        }
        ui.UiToggle(ctx, "Fonts", &editor.show_fonts)
        if editor.show_fonts {
            ui.UiLabelDim(ctx, "A font file for a face (empty: the built in one)")
            for face in Face {
                if ui.UiRow(ctx, {gap = 6, size = {ui.Grow(), ui.Fit()}}) {
                    ui.UiLabelDim(ctx, FaceKey(face))
                    ui.UiSpacer(ctx)
                    if changed_name, _ := ui.UiTextField(ctx, ui.UiFormat(ctx, "##font%d", int(face)), editor.fonts.files[face][:], &editor.fonts.lengths[face], {ui.Fixed(190), {}}); changed_name {
                        editor.fonts_serial += 1
                    }
                }
            }
        }
        ui.UiTextField(ctx, "##style_filter", editor.filter[:], &editor.filter_length, {ui.Grow(), {}})
        // the fields: the ones the picked element is drawn with first
        filter: string = string(editor.filter[:editor.filter_length])
        if ui.UiScroll(ctx, "fields", {ui.Grow(), ui.Fixed(170)}, {direction = .TOP_TO_BOTTOM, gap = 2}) {
            for pass in 0 ..< 2 {
                for i in 0 ..< ThemeFieldCount() {
                    name: string = ThemeFieldName(i)
                    kind: ThemeFieldKind = ThemeFieldKindOf(i)
                    if kind == .NONE || !styleFieldMatches(name, filter) { continue }
                    used: bool = was_picked && editor.pick && styleFieldUsed(picked.kind, name, ui.EditTargetName(&picked))
                    if used != (pass == 0) { continue }
                    ui.ElementOpen(ctx, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 6, align = {y = .CENTER}}})
                    if kind == .COLOR {
                        ui.ElementOpen(ctx, {layout = {size = {ui.Fixed(18), ui.Fixed(18)}}, draw = {kind = .SWATCH, color = ThemeFieldColor(&editor.theme, i)^}})
                        ui.ElementClose(ctx)
                    }
                    label: string = ui.UiFormat(ctx, "%s%s##field%d", "* " if used else "", name, i)
                    if ui.UiSelectable(ctx, label, editor.selected == i, {ui.Grow(), {}}) { editor.selected = i }
                    ui.ElementClose(ctx)
                }
            }
        }
        // the field that is edited
        if editor.selected >= 0 && editor.selected < ThemeFieldCount() {
            index: int = editor.selected
            name: string = ThemeFieldName(index)
            switch ThemeFieldKindOf(index) {
            case .COLOR:
                color: ^ui.Color = ThemeFieldColor(&editor.theme, index)
                editor.rgb = {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255}
                editor.alpha = f32(color.a) / 255
                if ui.UiColorPicker(ctx, ui.UiFormat(ctx, "color##%d", index), &editor.rgb, &editor.alpha, 110) {
                    color^ = {u8(clamp(editor.rgb.r, 0, 1) * 255 + 0.5), u8(clamp(editor.rgb.g, 0, 1) * 255 + 0.5), u8(clamp(editor.rgb.b, 0, 1) * 255 + 0.5), u8(clamp(editor.alpha, 0, 1) * 255 + 0.5)}
                    changed = true
                }
            case .NUMBER:
                low, high := styleNumberRange(name)
                if ui.UiSlider(ctx, ui.UiFormat(ctx, "%s##number%d", name, index), ThemeFieldNumber(&editor.theme, index), low, high, {ui.Grow(), {}}) { changed = true }
            case .FLAG:
                if ui.UiToggle(ctx, ui.UiFormat(ctx, "%s##flag%d", name, index), ThemeFieldFlag(&editor.theme, index)) { changed = true }
            case .NONE:
            }
        }
    }
    return
}
