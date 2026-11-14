package AppState
import "core:testing"

AppState :: struct {
    enter: proc(),
    exit: proc(),
    update: proc(),
    draw: proc(),
    name: string,
}

AppStatePtr :: ^AppState

AppStateChange :: proc(current: ^AppStatePtr, new_state: ^AppState){
    if new_state == current^ {
        return
    }
    // the state that is being left exits, not the one that is entered
    if current^ != nil && current^.exit != nil {
        current^.exit()
    }

    current^ = new_state

    if current^.enter != nil {
        current^.enter()
    }
}

// --- Tests ---

@(private="file", thread_local)
calls: [8]string
@(private="file", thread_local)
call_count: int

@(private="file")
record :: proc(what: string) {
    calls[call_count] = what
    call_count += 1
}

@(private="file")
enter_a :: proc() { record("enter a") }
@(private="file")
exit_a :: proc() { record("exit a") }
@(private="file")
enter_b :: proc() { record("enter b") }
@(private="file")
exit_b :: proc() { record("exit b") }

@(test)
test_app_state_change_runs_exit_then_enter :: proc(t: ^testing.T) {
    call_count = 0
    a: AppState = {enter = enter_a, exit = exit_a, name = "a"}
    b: AppState = {enter = enter_b, exit = exit_b, name = "b"}
    current: AppStatePtr = &a

    AppStateChange(&current, &b)
    testing.expect(t, current == &b)
    testing.expect_value(t, call_count, 2)
    testing.expect_value(t, calls[0], "exit a")                                    // the state being left is the one that exits
    testing.expect_value(t, calls[1], "enter b")

    AppStateChange(&current, &b)                                                   // same state: nothing happens
    testing.expect_value(t, call_count, 2)
}

@(test)
test_app_state_change_tolerates_missing_callbacks :: proc(t: ^testing.T) {
    call_count = 0
    bare: AppState = {name = "bare"}
    b: AppState = {enter = enter_b, name = "b"}

    current: AppStatePtr = nil                                                     // the very first state
    AppStateChange(&current, &bare)
    testing.expect(t, current == &bare)
    testing.expect_value(t, call_count, 0)

    AppStateChange(&current, &b)
    AppStateChange(&current, &bare)
    testing.expect_value(t, call_count, 1)
    testing.expect_value(t, calls[0], "enter b")
}
