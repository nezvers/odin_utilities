package game

GameState :: struct {
    init: proc(),
    finit: proc(),
    update: proc(),
    draw: proc(),
    gui: proc(),
}

current_state: GameState

change_game_state :: proc(new_state: GameState) {
    if (current_state.finit != nil) {
        current_state.finit()
    }
    current_state = new_state
    
    if (current_state.init != nil) {
        current_state.init()
    }
}