#+private file
package demo_common

// Two effects in a SoundBank: the buttons trigger them. A trigger too soon after the last one is blocked, a quick repeat raises the pitch,
// and the pitch starts at a random value so the same sound is not robotic. The sliders change the settings of the effect.

import "core:fmt"
import sfx ".."
import kit "../../demo_kit"

@(private="package")
demo_sfx: kit.Demo = {
    name = "sound effects",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

BUTTON :: sfx.SoundId(1)
DAMAGE :: sfx.SoundId(2)

settings: [3]sfx.SoundSettings
states: [3]sfx.SoundState
bank: sfx.SoundBank
sounds: [3]kit.Sound
triggered: [3]int       // how many times each was asked
played: [3]int          // and how many were not blocked
last_pitch: [3]f32

init :: proc(ctx: ^kit.Context) {
    settings[BUTTON] = {
        volume = 1,
        pitch_rand_min = 0.9,
        pitch_rand_max = 1.2,
        pitch_min = 0.5,
        pitch_max = 1.75,
        pitch_increment = 0.01,     // Pitch change on fast retrigger
        retrigger_treshold = 0.02,  // Do not play if sooner than this
        retrigger_interval = 0.5,   // Apply pitch_increment
        pitch_return = 1,           // Time to return to the starting pitch
    }
    settings[DAMAGE] = {
        volume = 0.5,
        pitch_rand_min = 0.9,
        pitch_rand_max = 1.2,
        pitch_min = 0.5,
        pitch_max = 1.75,
        pitch_increment = 0.01,
        retrigger_treshold = 0.25,
        retrigger_interval = 0.5,
        pitch_return = 1,
    }
    sfx.SoundBankInit(&bank, settings[:], states[:])
    sounds[BUTTON] = kit.SoundLoad(ctx, #load("../../assets/sounds/button_sound.wav"))
    sounds[DAMAGE] = kit.SoundLoad(ctx, #load("../../assets/sounds/damage_sound.wav"))
    triggered, played, last_pitch = {}, {}, {}
}

finit :: proc(ctx: ^kit.Context) {
    kit.SoundUnload(ctx, sounds[BUTTON])
    kit.SoundUnload(ctx, sounds[DAMAGE])
}

play :: proc(ctx: ^kit.Context, id: sfx.SoundId) {
    triggered[id] += 1
    volume, pitch, ok := sfx.SoundBankTrigger(&bank, id, ctx.time)
    if !ok { return }
    played[id] += 1
    last_pitch[id] = pitch
    kit.SoundPlay(ctx, sounds[id], volume, pitch)
}

update :: proc(ctx: ^kit.Context) {
}

// the widgets are drawn and read in the same place, like an immediate mode gui does
draw :: proc(ctx: ^kit.Context) {
    if kit.Button(ctx, {10, 10, 150, 25}, "Button Sound") { play(ctx, BUTTON) }
    if kit.Button(ctx, {10, 40, 150, 25}, "Damage Sound") { play(ctx, DAMAGE) }

    kit.DrawText(ctx, fmt.tprintf("button: asked %d, played %d, pitch %.2f", triggered[BUTTON], played[BUTTON], last_pitch[BUTTON]), {180, 12}, 18, kit.BLACK)
    kit.DrawText(ctx, fmt.tprintf("damage: asked %d, played %d, pitch %.2f", triggered[DAMAGE], played[DAMAGE], last_pitch[DAMAGE]), {180, 42}, 18, kit.BLACK)

    // settings of the damage effect
    kit.Slider(ctx, {10, 100, 350, 22}, "volume", &settings[DAMAGE].volume, 0, 1)
    kit.Slider(ctx, {10, 130, 350, 22}, "retrigger treshold", &settings[DAMAGE].retrigger_treshold, 0, 1)
    kit.Slider(ctx, {10, 160, 350, 22}, "pitch increment", &settings[DAMAGE].pitch_increment, 0, 0.2)
    kit.DrawText(ctx, "damage settings: a trigger sooner than the retrigger treshold is blocked, a quick repeat raises the pitch", {10, 200}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Click({50, 20}),                // button sound
    kit.Wait(10),
    kit.Click({50, 20}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return triggered[BUTTON] == 2 && played[BUTTON] == 2 }, "the button effect has a tiny treshold: two clicks 0.2 seconds apart both play"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return last_pitch[BUTTON] >= 0.5 && last_pitch[BUTTON] <= 1.75 }, "the pitch stays inside of its limits"),
    kit.Click({50, 50}),                // damage sound
    kit.Wait(3),
    kit.Click({50, 50}),                // too soon: 0.25 s treshold
    kit.Check(proc(ctx: ^kit.Context) -> bool { return triggered[DAMAGE] == 2 && played[DAMAGE] == 1 }, "the damage effect blocks a trigger that comes too soon"),
    kit.Wait(30),
    kit.Click({50, 50}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return played[DAMAGE] == 2 }, "and plays again after the treshold"),
    // drag the volume slider to the middle
    kit.Drag({10 + 60, 111}, {10 + 60 + 145, 111}, 5),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return settings[DAMAGE].volume > 0.3 && settings[DAMAGE].volume < 0.9 }, "the slider changes the setting"),
}
