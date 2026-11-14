package sound_effects

import "core:math/rand"
import "base:intrinsics"
import "core:testing"

SoundEffect::struct{
    volume:f32,
    pitch_rand_min:f32,
    pitch_rand_max:f32,
    pitch_min:f32,
    pitch_max:f32,
    pitch_increment:f32,    // For fast repeated trigger
    retrigger_treshold:f32, // How soon can be triggered again
    retrigger_interval:f32, // If triggered in this time again, a pitch is added
    pitch_return:f32,       // Time to return to original pitch
    // Calculated at trigger
    pitch:f32,              // Current pitch
    last_time:f64,          // Keep track of trigger time
}

@(private="file")
UpdatePitch::proc(sound:^SoundEffect, delta:f32){
    if delta < sound.retrigger_interval {
        if sound.pitch > sound.pitch_max {
            sound.pitch = sound.pitch_max + (Lerp(sound.pitch_rand_min, sound.pitch_rand_max, rand.float32()) - 1)
        } else 
        if sound.pitch < sound.pitch_min {
            sound.pitch = sound.pitch_min + (Lerp(sound.pitch_rand_min, sound.pitch_rand_max, rand.float32()) - 1)
        } else {
            sound.pitch += sound.pitch_increment
        }
    } else
    if delta < sound.retrigger_interval + sound.pitch_return {
        pitch_default:f32 = Lerp(sound.pitch_rand_min, sound.pitch_rand_max, 0.5)
        t:f32 = (delta - sound.retrigger_interval) / sound.pitch_return
        sound.pitch = Lerp(sound.pitch, pitch_default, t)
    } else {
        sound.pitch = Lerp(sound.pitch_rand_min, sound.pitch_rand_max, rand.float32())
    }
}

@(private="file")
Lerp::proc(a:$T, b:T, t:T)->T
where intrinsics.type_is_float(T)
{
    return a + (b - a) * t
}

Play::proc(sound:^SoundEffect, time_seconds:f64)->bool {
    if time_seconds < sound.last_time + cast(f64)sound.retrigger_treshold {
        return false
    }
    delta:f32 = cast(f32)(time_seconds - sound.last_time)
    sound.last_time = time_seconds
    UpdatePitch(sound, delta)
    return true
}

// --- Tests ---

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
