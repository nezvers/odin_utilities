package sound_effects

// Sound effects with a pitch that follows how fast they are triggered (a gun that rises in pitch when it is held, a hit that is not
// the same every time). Framework agnostic: this decides IF a sound plays and with what volume and pitch, the glue plays it.
//
// Data and state are separate:
//   SoundSettings - the tuning of one effect, constant data, shared by every user of the effect (a table, a prefab field by id)
//   SoundState    - what changes while playing (the current pitch, when it was last triggered), a few bytes per effect
// A SoundBank is the table of settings and the table of states side by side, addressed by SoundId: plain integers that can be put
// in prefab data, saved in a level file and survive a hot reload, where pointers to globals do not. The states are an array
// the user provides, for example in the game memory.
// SoundEffect keeps both together in one struct, for the simple case of one effect.
// This package builds for js_wasm32 (a web game uses it), the tests are in sound_effects_test.odin.

import "core:math/rand"
import "base:intrinsics"

SoundSettings :: struct {
    volume:f32,
    pitch_rand_min:f32,
    pitch_rand_max:f32,
    pitch_min:f32,
    pitch_max:f32,
    pitch_increment:f32,    // For fast repeated trigger
    retrigger_treshold:f32, // How soon can be triggered again
    retrigger_interval:f32, // If triggered in this time again, a pitch is added
    pitch_return:f32,       // Time to return to original pitch
}

SoundState :: struct {
    pitch:f32,              // Current pitch, calculated at trigger
    last_time:f64,          // Keep track of trigger time
}

// One effect: settings and state together
SoundEffect::struct{
    using settings: SoundSettings,
    using state: SoundState,
}

@(private="file")
Lerp::proc(a:$T, b:T, t:T)->T
where intrinsics.type_is_float(T)
{
    return a + (b - a) * t
}

@(private="file")
UpdatePitch::proc(settings:^SoundSettings, state:^SoundState, delta:f32){
    if delta < settings.retrigger_interval {
        if state.pitch > settings.pitch_max {
            state.pitch = settings.pitch_max + (Lerp(settings.pitch_rand_min, settings.pitch_rand_max, rand.float32()) - 1)
        } else
        if state.pitch < settings.pitch_min {
            state.pitch = settings.pitch_min + (Lerp(settings.pitch_rand_min, settings.pitch_rand_max, rand.float32()) - 1)
        } else {
            state.pitch += settings.pitch_increment
        }
    } else
    if delta < settings.retrigger_interval + settings.pitch_return {
        pitch_default:f32 = Lerp(settings.pitch_rand_min, settings.pitch_rand_max, 0.5)
        t:f32 = (delta - settings.retrigger_interval) / settings.pitch_return
        state.pitch = Lerp(state.pitch, pitch_default, t)
    } else {
        state.pitch = Lerp(settings.pitch_rand_min, settings.pitch_rand_max, rand.float32())
    }
}

// Decide whether the effect plays now. False: too soon after the last time. True: the new pitch is in `state.pitch`
SoundTrigger::proc(settings:^SoundSettings, state:^SoundState, time_seconds:f64)->bool {
    if time_seconds < state.last_time + cast(f64)settings.retrigger_treshold {
        return false
    }
    delta:f32 = cast(f32)(time_seconds - state.last_time)
    state.last_time = time_seconds
    UpdatePitch(settings, state, delta)
    return true
}

// The same for a SoundEffect
Play::proc(sound:^SoundEffect, time_seconds:f64)->bool {
    return SoundTrigger(&sound.settings, &sound.state, time_seconds)
}

// --- A table of effects ---

// Index into a SoundBank. 0 is no sound: put an unused row first, it is never played
SoundId :: distinct u16
SOUND_NONE :: SoundId(0)

SoundBank :: struct {
    settings: []SoundSettings,      // constant data, one row per effect
    states: []SoundState,           // same length, the user's memory
}

// `states` has the length of `settings`. They are reset. Call again with the new `settings` after a hot reload (states are kept)
SoundBankInit :: proc(bank:^SoundBank, settings:[]SoundSettings, states:[]SoundState) {
    assert(len(settings) == len(states))
    bank^ = {settings = settings, states = states}
    for &state in states { state = {} }
}

// Point the bank at the settings of new code, the states stay
SoundBankRebind :: proc(bank:^SoundBank, settings:[]SoundSettings) {
    assert(len(settings) == len(bank.states))
    bank.settings = settings
}

// Trigger an effect by id. Returns the volume and the pitch to play with, ok is false when it should not play: no such sound,
// or too soon after the last time
SoundBankTrigger::proc(bank:^SoundBank, id:SoundId, time_seconds:f64)->(volume:f32, pitch:f32, ok:bool) {
    if id == SOUND_NONE || int(id) >= len(bank.settings) { return }
    if !SoundTrigger(&bank.settings[id], &bank.states[id], time_seconds) { return }
    return bank.settings[id].volume, bank.states[id].pitch, true
}
