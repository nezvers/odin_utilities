#+build !js
package ui

import "core:testing"

@(private = "file")
measure :: proc(ctx: ^Context, text: string, font_size: f32) -> Vec2 {
    return {f32(len(text)) * font_size * 0.5, font_size}
}

@(test)
test_dates_know_their_months_and_weekdays :: proc(t: ^testing.T) {
    testing.expect(t, DateIsLeapYear(2024) && DateIsLeapYear(2000) && !DateIsLeapYear(1900) && !DateIsLeapYear(2026))
    testing.expect_value(t, DateDaysInMonth(2026, 2), 28)
    testing.expect_value(t, DateDaysInMonth(2024, 2), 29)
    testing.expect_value(t, DateDaysInMonth(2026, 11), 30)
    testing.expect_value(t, DateDaysInMonth(2026, 12), 31)
    testing.expect_value(t, DateDaysInMonth(2026, 13), 0)
    testing.expect(t, DateIsValid({2026, 11, 12}) && DateIsValid({2024, 2, 29}))
    testing.expect(t, !DateIsValid({2026, 2, 29}) && !DateIsValid({2026, 0, 1}) && !DateIsValid({2026, 4, 31}) && !DateIsValid({0, 1, 1}) && !DateIsValid({}))
    // 0 is a Monday
    testing.expect_value(t, DateWeekday({2026, 11, 12}), 3)             // a Thursday
    testing.expect_value(t, DateWeekday({1970, 1, 1}), 3)               // a Thursday
    testing.expect_value(t, DateWeekday({2000, 2, 29}), 1)              // a Tuesday
    testing.expect_value(t, DateWeekday({2024, 12, 30}), 0)             // a Monday
    testing.expect_value(t, DateWeekday({2026, 11, 1}), 6)              // a Sunday
    // a week on is the same day of the week, over the end of a month and of a year
    testing.expect_value(t, DateWeekday({2026, 12, 28}), DateWeekday({2027, 1, 4}))

    testing.expect_value(t, DateAddMonths({2026, 11, 12}, 1), Date{2026, 12, 12})
    testing.expect_value(t, DateAddMonths({2026, 11, 12}, 2), Date{2027, 1, 12})
    testing.expect_value(t, DateAddMonths({2026, 1, 31}, 1), Date{2026, 2, 28})         // February has no 31st
    testing.expect_value(t, DateAddMonths({2026, 1, 15}, -1), Date{2025, 12, 15})
    testing.expect_value(t, DateAddMonths({2026, 3, 15}, -27), Date{2023, 12, 15})
    testing.expect_value(t, DateAddMonths({1, 1, 15}, -5), Date{1, 1, 15})               // not before the first year
    buffer: [16]u8
    testing.expect_value(t, DateFormat(buffer[:], {2026, 11, 12}), "12/11/2026")
    testing.expect_value(t, DateFormat(buffer[:], {987, 3, 5}), "05/03/0987")
}

@(private = "file")
DateTest :: struct {
    storage: Storage(128, 256, 64, 2048),
    ctx: Context,
    style: Style,
    date: Date,
    minutes: int,
    date_changes: int,
    time_changes: int,
}

@(private = "file")
dateFrame :: proc(test: ^DateTest, input: Input) {
    UiBegin(&test.ctx, input, 1.0 / 60, {800, 700}, &test.style)
    if UiWindow(&test.ctx, "window", {0, 0}, {Fixed(400), {}}) {
        if UiDateField(&test.ctx, "date", &test.date) { test.date_changes += 1 }
        if UiTimeField(&test.ctx, "time", &test.minutes, 30) { test.time_changes += 1 }
    }
    UiEnd(&test.ctx)
}

@(private = "file")
clickAt :: proc(test: ^DateTest, point: Vec2) {
    dateFrame(test, {mouse_position = point})
    dateFrame(test, {mouse_position = point, mouse_down = true, mouse_pressed = true})
    dateFrame(test, {mouse_position = point, mouse_released = true})
    dateFrame(test, {mouse_position = {-100, -100}})
}

@(private = "file")
centerOf :: proc(t: ^testing.T, test: ^DateTest, id: Id, wanted: bool = true) -> Vec2 {
    rect, found := UiElementRect(&test.ctx, id)
    testing.expect_value(t, found && rect.z > 0, wanted)
    return {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
}

@(test)
test_a_date_field_opens_a_month_and_takes_the_day_that_is_clicked :: proc(t: ^testing.T) {
    test: ^DateTest = new(DateTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.date = {2026, 11, 12}
    test.minutes = 7 * 60 + 30
    for _ in 0 ..< 3 { dateFrame(test, {mouse_position = {-100, -100}}) }
    field: Id = UiIdPath("window", "date")
    popup: Id = IdFromString("popup", field)
    // the field shows the date and carries the picture of a calendar; the month is closed
    shown: bool
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.id == field {
            shown = command.info.kind == .DROPDOWN && command.info.text == "12/11/2026" && command.info.icon == .CALENDAR
        }
    }
    testing.expect(t, shown)
    centerOf(t, test, popup, false)

    clickAt(test, centerOf(t, test, field))
    centerOf(t, test, popup)
    // November 2026 has 30 days: a cell for each, the 12th marked, no 31st
    cells, marked: int
    title: bool
    for command in UiCommands(&test.ctx) {
        if command.kind != .DRAW { continue }
        if command.info.kind == .DATE_CELL {
            cells += 1
            if .SELECTED in command.info.flags {
                marked += 1
                testing.expect_value(t, command.info.name, "12")
            }
        }
        if command.info.kind == .LABEL && command.info.text == "November 2026" { title = true }
    }
    testing.expect_value(t, cells, 30)
    testing.expect_value(t, marked, 1)
    testing.expect(t, title, "the month and the year are the title")
    // the first of the month is a Sunday: it is the last cell of the first week, the second starts the next row
    first, _ := UiElementRect(&test.ctx, IdFromIndex(1, popup))
    second, _ := UiElementRect(&test.ctx, IdFromIndex(2, popup))
    testing.expect(t, second.y > first.y && second.x < first.x)

    // a click on the 20th takes it and closes the month
    clickAt(test, centerOf(t, test, IdFromIndex(20, popup)))
    testing.expect_value(t, test.date, Date{2026, 11, 20})
    testing.expect_value(t, test.date_changes, 1)
    centerOf(t, test, popup, false)

    // the arrows go a month on and back; the day of the date is only marked in its own month
    clickAt(test, centerOf(t, test, field))
    clickAt(test, centerOf(t, test, IdFromString("forward", popup)))
    december, marked_december: int
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.kind == .DATE_CELL {
            december += 1
            if .SELECTED in command.info.flags { marked_december += 1 }
        }
    }
    testing.expect_value(t, december, 31)
    testing.expect_value(t, marked_december, 0)
    testing.expect_value(t, test.date, Date{2026, 11, 20})               // looking at another month changes nothing
    clickAt(test, centerOf(t, test, IdFromString("forward", popup)))
    clickAt(test, centerOf(t, test, IdFromIndex(3, popup)))
    testing.expect_value(t, test.date, Date{2027, 1, 3})
    testing.expect_value(t, test.date_changes, 2)
    clickAt(test, centerOf(t, test, field))
    clickAt(test, centerOf(t, test, IdFromString("back", popup)))
    clickAt(test, centerOf(t, test, IdFromIndex(31, popup)))
    testing.expect_value(t, test.date, Date{2026, 12, 31})

    // the day that is the date already: taken again, nothing changed
    clickAt(test, centerOf(t, test, field))
    clickAt(test, centerOf(t, test, IdFromIndex(31, popup)))
    testing.expect_value(t, test.date_changes, 3)
    // a press outside closes the month
    clickAt(test, centerOf(t, test, field))
    centerOf(t, test, popup)
    clickAt(test, {700, 650})
    centerOf(t, test, popup, false)
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}

@(test)
test_a_time_field_lists_the_times_of_a_day_in_steps :: proc(t: ^testing.T) {
    test: ^DateTest = new(DateTest)
    defer free(test)
    test.style = {metrics = DEFAULT_METRICS}
    UiInit(&test.ctx, &test.storage, measure)
    test.date = {2026, 11, 12}
    test.minutes = 7 * 60 + 30
    for _ in 0 ..< 3 { dateFrame(test, {mouse_position = {-100, -100}}) }
    field: Id = UiIdPath("window", "time")
    shown: string
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.id == field { shown = command.info.text }
    }
    testing.expect_value(t, shown, "07:30")
    // a time between two steps is shown as the step before it, and left alone until a time is picked
    test.minutes = 7 * 60 + 44
    dateFrame(test, {mouse_position = {-100, -100}})
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.id == field { shown = command.info.text }
    }
    testing.expect_value(t, shown, "07:30")
    testing.expect_value(t, test.minutes, 7 * 60 + 44)
    testing.expect_value(t, test.time_changes, 0)
    // out of the day: the first or the last time
    test.minutes = 5000
    dateFrame(test, {mouse_position = {-100, -100}})
    for command in UiCommands(&test.ctx) {
        if command.kind == .DRAW && command.info.id == field { shown = command.info.text }
    }
    testing.expect_value(t, shown, "23:30")
    testing.expect_value(t, UiProblems(&test.ctx), Problems{})
}
