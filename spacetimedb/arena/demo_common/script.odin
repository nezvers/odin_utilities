#+build !js
package demo_common

import kit "../../../demo_kit"
import game_lib "../game"

// The test of the demo: a solo game (the program starts its own server), the player holds right and then left, and has to have moved on the field. The headless run has no real time, so
// the demo sleeps in every frame (`config.sleep_ms`) to give the network and the 20 steps per second of the server the time they need.
script: []kit.Step = {
    kit.Wait(3),
    kit.Click({640, 312}),                  // "Play solo" when the start screen is there (a window run has no arguments); harmless on the field
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING }, "the solo game started its server and opened the game"),
    kit.Wait(1200),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.game.phase == .PLAYING && state.game.player_count == 1 && state.game.coin_count > 0 }, "the player joined and the coins are on the field"),
    kit.Hold(.D, 500),
    kit.Hold(.A, 500),
    kit.Wait(100),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.max_x - state.min_x > 30 }, "the player moved when the keys were held"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        me, found := game_lib.GameMe(state.game)
        return found && me.x >= 0 && me.x <= game_lib.FIELD_WIDTH
    }, "and stayed on the field"),
}
