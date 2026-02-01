package sound_effects

import "core:math/rand"
import "base:intrinsics"

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
GetPitch::proc(sound:^SoundEffect, delta:f32){
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
    GetPitch(sound, delta)
    return true
}