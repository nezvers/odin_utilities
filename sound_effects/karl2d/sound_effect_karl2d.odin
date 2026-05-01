package sound_effect_karl2d

import sfx ".."
import "../../karl2d"

Init::proc(sound_effect:^sfx.SoundEffect, sound: ^karl2d.Sound){
    karl2d.set_sound_volume(sound^, sound_effect.volume)
}

Play::proc(sound_effect:^sfx.SoundEffect, time_seconds:f64, sound: ^karl2d.Sound){
    if !sfx.Play(sound_effect, time_seconds){
        return
    }
    // Not neccessary to change volume each time
    // rl.SetSoundVolume(sound^, sound_effect.volume)

    karl2d.set_sound_pitch(sound^, sound_effect.pitch)
    karl2d.play_sound(sound^)
}