#+build !js
package demo_common

import kit "../../../demo_kit"
import game_lib "../game"

// The test of the demo: a solo game (the program starts its own server), the player holds right and then left, and has to have moved on the field. The headless run has no real time, so
// the demo sleeps in every frame (`config.sleep_ms`) to give the network and the 20 steps per second of the server the time they need.
@(private = "file")
start_x: f32                    // where the player was when the keys were pressed
@(private = "file")
turn_x: f32                     // where it was when it turned

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.name_length = copy(state.name[:], "player"); return true }, "a fixed name for the picture"),
    kit.Wait(2),
    kit.Capture("start_screen"),            // only in a window run with the captures on; a window of this size shows the start screen
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase != .MENU || aimPlaySolo(ctx) }, "the start screen has Play solo (a window run has no arguments)"),
    kit.ClickAt(&target),                   // on the start screen it starts the game; when the game runs already it lands on the field and does nothing
    // everything that takes the time of a server (it starts, the game joins, the player moves) is waited for, never slept: the server is another program on its own clock, and a fixed wait
    // is right on a quiet computer and short on a busy one
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING }, "the solo game started its server and opened the game", 6000),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return state.game.phase == .PLAYING && state.game.player_count == 1 && state.game.coin_count > 0 }, "the player joined and the coins are on the field", 6000),
    // right: the key is held until the player has moved right (the 20 steps a second of the server decide how long that takes)
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        me, found := game_lib.GameMe(state.game)
        start_x = me.x if found else 0
        return found
    }, "the player is on the field"),
    kit.KeyDownStep(.D),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool {
        me, found := game_lib.GameMe(state.game)
        return found && (me.x > start_x + 40 || me.x >= game_lib.FIELD_WIDTH - 15)       // far enough, or at the edge (the player starts anywhere on the field)
    }, "the player moved right while D was held", 6000),
    kit.KeyUpStep(.D),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        me, found := game_lib.GameMe(state.game)
        turn_x = me.x if found else 0
        return found
    }, "the player stopped"),
    // and left
    kit.KeyDownStep(.A),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool {
        me, found := game_lib.GameMe(state.game)
        return found && (me.x < turn_x - 40 || me.x <= 15)
    }, "the player moved left while A was held", 6000),
    kit.KeyUpStep(.A),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.max_x - state.min_x > 30 }, "the window noted the movement"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        me, found := game_lib.GameMe(state.game)
        return found && me.x >= 0 && me.x <= game_lib.FIELD_WIDTH
    }, "and stayed on the field"),
}
