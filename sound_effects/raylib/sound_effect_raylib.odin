package sound_effect_raylib

import sf ".."
import rl "vendor:raylib"

Init::proc(sound_effect:^sf.SoundEffect, sound: ^rl.Sound){
    rl.SetSoundVolume(sound^, sound_effect.volume)
}

Play::proc(sound_effect:^sf.SoundEffect, time_seconds:f64, sound: ^rl.Sound){
    if !sf.Play(sound_effect, time_seconds){
        return
    }
    // Not neccessary to change volume each time
    // rl.SetSoundVolume(sound^, sound_effect.volume)
    rl.SetSoundPitch(sound^, sound_effect.pitch)
    rl.PlaySound(sound^)
}