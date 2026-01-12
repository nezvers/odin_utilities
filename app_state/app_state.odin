package AppState

AppState :: struct {
    enter: proc(),
    exit: proc(),
    update: proc(),
    draw: proc(),
}

AppStatePtr :: ^AppState

AppStateChange :: proc(current: ^AppStatePtr, new_state: ^AppState){
    if new_state == current^ {
        return
    }
    if new_state.exit != nil {
        new_state.exit()
    }

    current^ = new_state

    if current^.enter != nil {
        current^.exit()
    }
}