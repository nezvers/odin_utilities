package ui

// The windows almost every program has, made of the widgets of the library: a question with buttons (save changes? delete?), an about window, a welcome screen with recent files, a progress
// window, and the preferences window with a list of categories and a page for the one that is chosen. All are modals (`UiModal`): nothing under them reacts, Escape closes them. What a window
// says is the program's (names, texts, the page of a category).
//
//     UiConfirm(&ctx, "Save changes?", &open, "The project has changes that are not saved.", {"Save", "Don't save", "Cancel"}) -> the index of the button, -1 for none yet
//     UiAboutDialog(&ctx, "About", &open, {name = "Nota", version = "0.60", description = "A DAW.", credits = "Made with Odin."})
//     action, recent := UiWelcome(&ctx, "Welcome", &open, {headline = "Nota", actions = {"New project", "Open..."}, recent = files[:]})
//     cancelled := UiProgressDialog(&ctx, "Exporting", &open, "Writing the file...", fraction)
//     if UiPreferences(&ctx, "Preferences", &open, {"General", "Audio", "Shortcuts"}, &page) { switch page { case 0: ... } }        // the page is what you declare inside
//
//     UiWhatsNew(&ctx, "What is new", &open, releases[:], unseen = WhatsNewUnseen(releases[:], last_seen_version))
//
// Limits: one row of buttons (they do not wrap), texts wrap by words in a fixed width, no icons or pictures in a dialog (a program adds them around the call by using `UiModal` itself), the
//     welcome screen shows at most WELCOME_RECENT (8) recent entries, preferences has no search and no "apply" (the program applies what the controls change at once), the progress dialog
//     has one bar and one message, the what is new window shows releases newest first as markdown (no images, no "do not show again": the program keeps what version was seen).

WELCOME_RECENT :: 8

// The window with a question: a title (the name of the window, the text before "##"), a message and a row of buttons on the right. The index of the button that was clicked, -1 for none; the
// window closes with a click. `danger`: the index of a button that is drawn as the destructive one (-1 for none).
UiConfirm :: proc(ctx: ^Context, name: string, open: ^bool, message: string, buttons: []string, width: f32 = 380, danger: int = -1) -> (clicked: int) {
    clicked = -1
    if UiModal(ctx, name, open, {Fixed(width), {}}) {
        UiTitle(ctx, IdSplitName(name))
        UiLabel(ctx, message, .WORDS)
        if UiRow(ctx, {gap = 8, size = {Grow(), {}}}) {
            UiSpacer(ctx)
            for label, i in buttons {
                if i == danger {
                    if UiTagged(ctx, "danger") {
                        if UiButton(ctx, label) { clicked = i }
                    }
                } else if i < len(buttons) - 1 || len(buttons) == 1 {
                    if UiButton(ctx, label) { clicked = i }
                } else if UiTagged(ctx, "outline") {
                    if UiButton(ctx, label) { clicked = i }
                }
            }
        }
        if clicked >= 0 { open^ = false }
    }
    return
}

AboutInfo :: struct {
    name: string,
    version: string,
    description: string,
    credits: string,                // the people and libraries, wrapped
    copyright: string,
}

UiAboutDialog :: proc(ctx: ^Context, name: string, open: ^bool, info: AboutInfo, width: f32 = 380) {
    if UiModal(ctx, name, open, {Fixed(width), {}}) {
        UiTitle(ctx, info.name, 1.6)
        if info.version != "" { UiLabelDim(ctx, UiFormat(ctx, "Version %s", info.version)) }
        if info.description != "" { UiLabel(ctx, info.description, .WORDS) }
        if info.credits != "" {
            UiSeparator(ctx)
            UiLabelDim(ctx, info.credits, .WORDS)
        }
        if info.copyright != "" { UiLabelDim(ctx, info.copyright, .WORDS, 0.85) }
        if UiRow(ctx, {size = {Grow(), {}}}) {
            UiSpacer(ctx)
            if UiButton(ctx, "Close") { open^ = false }
        }
    }
}

WelcomeInfo :: struct {
    headline: string,
    tagline: string,
    actions: []string,              // the big buttons (New, Open, ...)
    recent: []string,               // names of the recent files, the newest first
}

// The welcome screen: the headline, the actions as buttons and the recent files as a list. Returns the action that was clicked and the recent file that was clicked (-1 for none); the window
// closes on either.
UiWelcome :: proc(ctx: ^Context, name: string, open: ^bool, info: WelcomeInfo, width: f32 = 460) -> (action: int, recent: int) {
    action, recent = -1, -1
    if UiModal(ctx, name, open, {Fixed(width), {}}) {
        UiTitle(ctx, info.headline, 1.8)
        if info.tagline != "" { UiLabelDim(ctx, info.tagline, .WORDS) }
        if UiRow(ctx, {gap = 8}) {
            for label, i in info.actions {
                if UiButton(ctx, label) { action = i }
            }
        }
        if len(info.recent) > 0 {
            UiSeparator(ctx)
            UiLabelDim(ctx, "Recent")
            for file, i in info.recent {
                if i >= WELCOME_RECENT { break }
                if UiSelectable(ctx, UiFormat(ctx, "%s##recent%d", file, i), false) { recent = i }
            }
        }
        if UiRow(ctx, {size = {Grow(), {}}}) {
            UiSpacer(ctx)
            if UiButton(ctx, "Close") { open^ = false }
        }
        if action >= 0 || recent >= 0 { open^ = false }
    }
    return
}

// A window that shows how far a job is: `fraction` 0 .. 1 of the bar, a message above it and a Cancel button (`cancel_label` "" has none). True in the frame Cancel was clicked: the program
// stops the job and closes the window (`open` is not changed, the job decides).
UiProgressDialog :: proc(ctx: ^Context, name: string, open: ^bool, message: string, fraction: f32, cancel_label: string = "Cancel", width: f32 = 380) -> (cancelled: bool) {
    if UiModal(ctx, name, open, {Fixed(width), {}}) {
        UiTitle(ctx, IdSplitName(name))
        UiLabel(ctx, message, .WORDS)
        UiProgress(ctx, "##bar", clamp(fraction, 0, 1), 0, 1, {Grow(), {}}, "%.0f")
        if UiRow(ctx, {size = {Grow(), {}}}) {
            UiSpacer(ctx)
            if cancel_label != "" && UiButton(ctx, cancel_label) { cancelled = true }
        }
    }
    return
}

// The preferences window: a list of categories on the left, the page of the chosen one on the right and a Close button under both. Everything declared between the call and the end of its block is
// the page: `if UiPreferences(&ctx, "Preferences", &open, names, &page, {Fixed(640), Fixed(420)}) { ... }`. Escape or Close closes it.
@(deferred_in = UiPreferencesEnd)
UiPreferences :: proc(ctx: ^Context, name: string, open: ^bool, categories: []string, selected: ^int, size: Size = {}) -> bool {
    if !open^ || ctx.cancel_pending {
        modalOpen(ctx, name, open, size)                // closes itself on Escape and leaves one element for the end to close
        ElementOpen(ctx, {})
        ElementOpen(ctx, {})
        return false
    }
    selected^ = clamp(selected^, 0, max(len(categories) - 1, 0))
    modalOpen(ctx, name, open, widgetSizeOr(size, Fixed(ctx.style.metrics.control_width * 4.4), Fixed(ctx.style.metrics.control_height * 11)))
    UiTitle(ctx, IdSplitName(name))
    ElementOpen(ctx, {layout = {size = {Grow(), Grow()}, direction = .LEFT_TO_RIGHT, gap = ctx.style.metrics.gap}})
    if UiScroll(ctx, "##categories", {Fixed(ctx.style.metrics.control_width * 1.1), Grow()}, {padding = PaddingAll(4), gap = 2}) {
        for label, i in categories {
            if UiSelectable(ctx, UiFormat(ctx, "%s##cat%d", label, i), selected^ == i) { selected^ = i }
        }
    }
    // the page: its own scroll, so a long page does not push the Close button out
    ElementOpen(ctx, {layout = {size = {Grow(), Grow()}, direction = .TOP_TO_BOTTOM, gap = ctx.style.metrics.gap, padding = PaddingAll(4)}})
    return true
}

UiPreferencesEnd :: proc(ctx: ^Context, name: string, open: ^bool, categories: []string, selected: ^int, size: Size = {}) {
    if !open^ {
        ElementClose(ctx)
        ElementClose(ctx)
        UiModalEnd(ctx, name, open, size)
        return
    }
    ElementClose(ctx)                   // the page
    ElementClose(ctx)                   // the row of list and page
    if UiRow(ctx, {size = {Grow(), {}}}) {
        UiSpacer(ctx)
        if UiButton(ctx, "Close") { open^ = false }
    }
    UiModalEnd(ctx, name, open, size)
}

Release :: struct {
    version: string,
    date: string,
    notes: string,                  // markdown (UiMarkdown), alive until UiRender
}

// How many releases (the list is newest first) come before the one with `seen`: those are what a person has not read. All of them when `seen` is not in the list.
WhatsNewUnseen :: proc(releases: []Release, seen: string) -> int {
    for release, i in releases {
        if release.version == seen { return i }
    }
    return len(releases)
}

// The window of the changes of a program: every release with its version and date, then its notes as markdown; the first `unseen` ones carry a "New" mark. Closes with the button.
UiWhatsNew :: proc(ctx: ^Context, name: string, open: ^bool, releases: []Release, unseen: int = 0, width: f32 = 480, height: f32 = 360) {
    if UiModal(ctx, name, open, {Fixed(width), Fixed(height)}) {
        UiTitle(ctx, IdSplitName(name))
        if UiScroll(ctx, "##releases", {Grow(), Grow()}, {gap = 8, padding = PaddingAll(2)}) {
            for release, i in releases {
                if UiRow(ctx, {gap = 8, size = {Grow(), Fit()}, align = {y = .CENTER}}) {
                    UiTitle(ctx, UiFormat(ctx, "Version %s", release.version), 1.1)
                    if i < unseen { UiChip(ctx, UiFormat(ctx, "New##new%d", i), true) }
                    UiSpacer(ctx)
                    UiLabelDim(ctx, release.date)
                }
                UiMarkdown(ctx, release.notes, UiFormat(ctx, "notes%d", i))
                if i < len(releases) - 1 { UiSeparator(ctx) }
            }
        }
        if UiRow(ctx, {size = {Grow(), {}}}) {
            UiSpacer(ctx)
            if UiButton(ctx, "Close") { open^ = false }
        }
    }
}
