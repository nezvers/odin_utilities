package ui

// A date field and a time field. The date field shows a day as text and opens a month of days to pick from; the time field is a list of the times of a day in steps.
// The calendar is the one in use today (Gregorian), from year 1 on; a week starts with Monday. The fields of the gallery of Baldr were the model; the code is written for
// this library.
//
//     due: ui.Date = {2026, 11, 12}
//     if ui.UiDateField(&ctx, "Due date", &due) { ... }
//     alarm: int = 7 * 60 + 30                            // minutes after midnight
//     if ui.UiTimeField(&ctx, "Alarm", &alarm) { ... }

import "core:fmt"

Date :: struct {
    year: int,
    month: int,         // 1 to 12
    day: int,           // 1 to 31
}

DateIsLeapYear :: proc "contextless" (year: int) -> bool {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

// The days of a month (1 to 12) of a year; 0 for a month that is none
DateDaysInMonth :: proc "contextless" (year: int, month: int) -> int {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12:
        return 31
    case 4, 6, 9, 11:
        return 30
    case 2:
        return 29 if DateIsLeapYear(year) else 28
    }
    return 0
}

DateIsValid :: proc "contextless" (date: Date) -> bool {
    return date.year >= 1 && date.month >= 1 && date.month <= 12 && date.day >= 1 && date.day <= DateDaysInMonth(date.year, date.month)
}

// The day of the week: 0 Monday to 6 Sunday (Sakamoto's method)
DateWeekday :: proc "contextless" (date: Date) -> int {
    offsets: [12]int = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
    year: int = date.year - 1 if date.month < 3 else date.year
    sunday_first: int = (year + year / 4 - year / 100 + year / 400 + offsets[clamp(date.month, 1, 12) - 1] + date.day) % 7
    return (sunday_first + 6) % 7
}

// The date moved by a number of months (back for a negative one). A day the new month does not have becomes its last one.
DateAddMonths :: proc "contextless" (date: Date, months: int) -> Date {
    total: int = date.year * 12 + (date.month - 1) + months
    result: Date = {year = total / 12, month = total % 12 + 1}
    if total < 12 { result = {year = 1, month = 1} }
    result.day = clamp(date.day, 1, DateDaysInMonth(result.year, result.month))
    return result
}

// The date as day/month/year with leading zeros, into `buffer` (10 bytes)
DateFormat :: proc(buffer: []u8, date: Date) -> string {
    return fmt.bprintf(buffer, "%02d/%02d/%04d", date.day, date.month, date.year)
}

DATE_MONTH_NAMES: [12]string = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
DATE_WEEKDAY_NAMES: [7]string = {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}

// A field that shows `date` and opens a month to pick a day from: arrows go a month back and on, a click on a day takes it and closes the month. True in the frame the
// date changed. A date that is not valid is shown as it is and replaced by the first pick.
UiDateField :: proc(ctx: ^Context, name: string, date: ^Date, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    popup_id: Id = IdFromString("popup", id)
    if interaction.clicked {
        state.open = !state.open
        // the month that is shown is kept as a count of months (the state of a widget has a whole number to spare): it starts at the month of the date
        if state.open { state.cursor = max(date.year, 1) * 12 + clamp(date.month, 1, 12) - 1 }
    }
    if state.open && ctx.cancel_pending {
        state.open = false
        ctx.cancel_pending = false
        ctx.focus = id
    }
    flags: Flags = {.DISABLED} if disabled else {}
    if state.open { flags += {.OPEN} }
    text: string = UiFormat(ctx, "%02d/%02d/%04d", date.day, date.month, date.year)
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, textWidth(ctx, text) + metrics.padding.x * 2 + metrics.control_height, metrics.control_height)},
        hit = {} if disabled else {.INTERACTIVE},
        draw = {kind = .DROPDOWN, name = IdSplitName(name), text = text, icon = .CALENDAR, font_size = metrics.font_size, flags = flags},
    })
    ElementClose(ctx)
    ctx.last_id = id
    if !state.open { return }

    shown: Date = {year = state.cursor / 12, month = state.cursor % 12 + 1, day = 1}
    cell: f32 = metrics.control_height
    _ = stateGet(ctx, popup_id)
    ElementOpen(ctx, {
        id = popup_id,
        layout = {size = {Fit(), Fit()}, padding = PaddingAll(8), gap = 4, direction = .TOP_TO_BOTTOM},
        floating = {attach_to = .ELEMENT_WITH_ID, parent = id, parent_point = .LEFT_BOTTOM, element_point = .LEFT_TOP, offset = {0, 4}, z_index = 100, capture = true},
        hit = {.INTERACTIVE, .BLOCKER},
        draw = {kind = .PANEL, name = "dropdown", font_size = metrics.font_size},
    })
    over_popup: bool = ctx.hover == popup_id
    // the month and the year between two arrows
    ElementOpen(ctx, {layout = {size = {Fixed(cell * 7), Fixed(cell)}, direction = .LEFT_TO_RIGHT, align = {y = .CENTER}}})
    UiPushTag(ctx, "ghost")
    back: Id = IdFromString("back", popup_id)
    if UiInteract(ctx, back).clicked { state.cursor = max(state.cursor - 1, 12) }
    over_popup = over_popup || ctx.hover == back
    ElementOpen(ctx, {id = back, layout = {size = {Fixed(cell), Fixed(cell)}}, hit = {.INTERACTIVE}, draw = {kind = .BUTTON, icon = .CHEVRON_LEFT, font_size = metrics.font_size}})
    ElementClose(ctx)
    UiPopTag(ctx)
    ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .CENTER}}})
    UiPushTag(ctx, "title")
    TextOpen(ctx, UiFormat(ctx, "%s %d", DATE_MONTH_NAMES[shown.month - 1], shown.year))
    UiPopTag(ctx)
    ElementClose(ctx)
    UiPushTag(ctx, "ghost")
    forward: Id = IdFromString("forward", popup_id)
    if UiInteract(ctx, forward).clicked { state.cursor += 1 }
    over_popup = over_popup || ctx.hover == forward
    ElementOpen(ctx, {id = forward, layout = {size = {Fixed(cell), Fixed(cell)}}, hit = {.INTERACTIVE}, draw = {kind = .BUTTON, icon = .CHEVRON_RIGHT, font_size = metrics.font_size}})
    ElementClose(ctx)
    UiPopTag(ctx)
    ElementClose(ctx)
    // the names of the days of the week
    ElementOpen(ctx, {layout = {size = {Fit(), Fit()}, direction = .LEFT_TO_RIGHT}})
    UiPushTag(ctx, "dim")
    for weekday in DATE_WEEKDAY_NAMES {
        ElementOpen(ctx, {layout = {size = {Fixed(cell), Fit()}, direction = .LEFT_TO_RIGHT, align = {x = .CENTER}}})
        TextOpen(ctx, weekday, {font_size = metrics.font_size * 0.85})
        ElementClose(ctx)
    }
    UiPopTag(ctx)
    ElementClose(ctx)
    // six weeks: the days before the first and after the last of the month are empty
    first_weekday: int = DateWeekday(shown)
    days: int = DateDaysInMonth(shown.year, shown.month)
    for week in 0 ..< 6 {
        if week * 7 - first_weekday + 1 > days { break }
        ElementOpen(ctx, {layout = {size = {Fit(), Fit()}, direction = .LEFT_TO_RIGHT}})
        for weekday in 0 ..< 7 {
            day: int = week * 7 + weekday - first_weekday + 1
            if day < 1 || day > days {
                ElementOpen(ctx, {layout = {size = {Fixed(cell), Fixed(cell)}}})
                ElementClose(ctx)
                continue
            }
            cell_id: Id = IdFromIndex(u32(day), popup_id)
            picked: Interaction = UiInteract(ctx, cell_id)
            over_popup = over_popup || picked.hovered
            if picked.clicked {
                chosen: Date = {shown.year, shown.month, day}
                changed = chosen != date^
                date^ = chosen
                state.open = false
                ctx.focus = id
            }
            is_date: bool = date.year == shown.year && date.month == shown.month && date.day == day
            ElementOpen(ctx, {
                id = cell_id,
                layout = {size = {Fixed(cell), Fixed(cell)}},
                hit = {.INTERACTIVE},
                draw = {kind = .DATE_CELL, name = UiFormat(ctx, "%d", day), actual = f32(day), font_size = metrics.font_size, flags = {.SELECTED} if is_date else {}},
            })
            ElementClose(ctx)
        }
        ElementClose(ctx)
    }
    ElementClose(ctx)
    // a press anywhere else closes the month
    if ctx.input.mouse_pressed && !over_popup && ctx.hover != id && ctx.hover_root != popup_id { state.open = false }
    return
}

// The most times a time field lists (a step of 10 minutes over a day)
TIME_FIELD_OPTIONS :: 144

// A field that shows a time of the day and opens a list of the times in steps of `step` minutes to pick from; typing in the list finds a time ("07"). `minutes` is the
// time as minutes after midnight (it is brought to a step). True in the frame it changed.
UiTimeField :: proc(ctx: ^Context, name: string, minutes: ^int, step: int = 30, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    stride: int = max(step, 24 * 60 / TIME_FIELD_OPTIONS)
    count: int = 24 * 60 / stride
    options: [TIME_FIELD_OPTIONS]string
    for i in 0 ..< count {
        options[i] = UiFormat(ctx, "%02d:%02d", i * stride / 60, i * stride % 60)
    }
    selected: int = clamp(minutes^ / stride, 0, count - 1)
    if UiCombo(ctx, name, options[:count], &selected, size, 8, disabled) {
        minutes^ = selected * stride
        changed = true
    }
    return
}
