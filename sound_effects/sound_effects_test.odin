#+build !js
// Tests of sound_effects.odin. They are in their own file because the library is used by games with a web build, and core:testing
// does not compile for js_wasm32.
package sound_effects

import "core:testing"

@(private="file")
make_effect :: proc() -> SoundEffect {
    return {
        volume = 1,
        pitch_rand_min = 1, pitch_rand_max = 1,                                            // no random spread keeps the test exact
        pitch_min = 0.5, pitch_max = 1.5,
        pitch_increment = 0.1,
        retrigger_treshold = 0.05, retrigger_interval = 0.5, pitch_return = 1,
    }
}

@(test)
test_sound_effect_retrigger_threshold :: proc(t: ^testing.T) {
    effect: SoundEffect = make_effect()
    testing.expect(t, Play(&effect, 10), "the first trigger always plays")
    testing.expect(t, !Play(&effect, 10.01), "too soon after the last one")
    testing.expect_value(t, effect.last_time, f64(10))                                     // a refused trigger does not move the clock
    testing.expect(t, Play(&effect, 10.06))
}

@(test)
test_sound_effect_pitch_rises_on_fast_repeats :: proc(t: ^testing.T) {
    effect: SoundEffect = make_effect()
    Play(&effect, 10)
    testing.expect_value(t, effect.pitch, f32(1))

    Play(&effect, 10.2)                                                                    // inside the retrigger interval
    testing.expect(t, abs(effect.pitch - 1.1) < 1e-5)
    Play(&effect, 10.4)
    testing.expect(t, abs(effect.pitch - 1.2) < 1e-5)

    effect.pitch = 1.6                                                                     // above the ceiling it falls back to it
    Play(&effect, 10.6)
    testing.expect(t, abs(effect.pitch - 1.5) < 1e-5)
    effect.pitch = 0.2
    Play(&effect, 10.8)
    testing.expect(t, abs(effect.pitch - 0.5) < 1e-5, "and the floor")
}

@(test)
test_sound_effect_pitch_returns_when_left_alone :: proc(t: ^testing.T) {
    effect: SoundEffect = make_effect()
    Play(&effect, 10)
    effect.pitch = 1.4

    Play(&effect, 11)                                                                      // 0.5 s after the interval of a 1 s return
    testing.expect(t, abs(effect.pitch - 1.2) < 1e-4, "half way back to the default")

    Play(&effect, 20)                                                                      // long silence: a fresh pitch
    testing.expect_value(t, effect.pitch, f32(1))
}

@(test)
test_settings_and_state_are_separate_data :: proc(t: ^testing.T) {
    settings: SoundSettings = make_effect().settings
    first, second: SoundState                                                              // two users of one effect, each with its own state
    testing.expect(t, SoundTrigger(&settings, &first, 10))
    testing.expect(t, SoundTrigger(&settings, &second, 10), "the second user is not blocked by the first")
    SoundTrigger(&settings, &first, 10.2)
    testing.expect(t, abs(first.pitch - 1.1) < 1e-5)
    testing.expect_value(t, second.pitch, f32(1))                                          // untouched

    // the same through a SoundEffect: it is only the two together
    effect: SoundEffect = {settings = settings}
    Play(&effect, 10)
    Play(&effect, 10.2)
    testing.expect(t, abs(effect.state.pitch - first.pitch) < 1e-5)
    testing.expect_value(t, size_of(SoundSettings), 36)                                    // nine floats: a plain table row
}

@(test)
test_a_bank_plays_effects_by_id :: proc(t: ^testing.T) {
    table: [3]SoundSettings
    table[1] = make_effect().settings                                                      // row 0 is no sound
    table[2] = make_effect().settings
    table[2].volume = 0.4
    table[2].retrigger_treshold = 1
    states: [3]SoundState
    bank: SoundBank
    SoundBankInit(&bank, table[:], states[:])

    volume, pitch, ok := SoundBankTrigger(&bank, 1, 10)
    testing.expect(t, ok)
    testing.expect_value(t, volume, f32(1))
    testing.expect_value(t, pitch, f32(1))
    _, rising_pitch, again := SoundBankTrigger(&bank, 1, 10.2)
    testing.expect(t, again && abs(rising_pitch - 1.1) < 1e-5)

    quiet, _, second_ok := SoundBankTrigger(&bank, 2, 10)
    testing.expect(t, second_ok)
    testing.expect_value(t, quiet, f32(0.4))
    _, _, blocked := SoundBankTrigger(&bank, 2, 10.5)
    testing.expect(t, !blocked, "its own retrigger threshold of a second")
    _, _, other := SoundBankTrigger(&bank, 1, 10.7)
    testing.expect(t, other, "and effect 1 has its own")

    _, _, none := SoundBankTrigger(&bank, SOUND_NONE, 20)
    testing.expect(t, !none, "the none id plays nothing")
    _, _, far := SoundBankTrigger(&bank, 9, 20)
    testing.expect(t, !far, "an id past the table plays nothing")
}

@(test)
test_bank_keeps_its_states_when_the_settings_are_rebound :: proc(t: ^testing.T) {
    table: [2]SoundSettings
    table[1] = make_effect().settings
    states: [2]SoundState
    bank: SoundBank
    SoundBankInit(&bank, table[:], states[:])
    SoundBankTrigger(&bank, 1, 10)
    SoundBankTrigger(&bank, 1, 10.2)
    testing.expect(t, abs(states[1].pitch - 1.1) < 1e-5)

    reloaded: [2]SoundSettings                                                             // the new code has its own copy of the table
    reloaded[1] = make_effect().settings
    reloaded[1].pitch_increment = 0.3
    SoundBankRebind(&bank, reloaded[:])
    SoundBankTrigger(&bank, 1, 10.4)
    testing.expect(t, abs(states[1].pitch - 1.4) < 1e-5, "the pitch continues from where it was, with the new tuning")

    SoundBankInit(&bank, reloaded[:], states[:])
    testing.expect_value(t, states[1].pitch, f32(0))                                       // Init starts clean
}
