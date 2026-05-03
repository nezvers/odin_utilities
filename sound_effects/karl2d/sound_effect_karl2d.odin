package sound_effect_karl2d

import sfx ".."
import "../../karl2d"

SfxKarl2D :: struct {
    sound_effect:^sfx.SoundEffect,
    sound: ^karl2d.Sound,
}

Init :: proc(sound_effect:^sfx.SoundEffect, sound: ^karl2d.Sound)->SfxKarl2D {
    karl2d.set_sound_volume(sound^, sound_effect.volume)
    return {sound_effect, sound}
}

PlaySfxKarl2D :: proc(sound_effect: ^SfxKarl2D, time_seconds:f64) {
    assert(sound_effect != nil)
    Play(sound_effect.sound_effect, time_seconds, sound_effect.sound)
}

Play :: proc(sound_effect:^sfx.SoundEffect, time_seconds:f64, sound: ^karl2d.Sound){
    assert(sound_effect != nil)
    if !sfx.Play(sound_effect, time_seconds){
        return
    }
    // Not neccessary to change volume each time
    // rl.SetSoundVolume(sound^, sound_effect.volume)

    karl2d.set_sound_pitch(sound^, sound_effect.pitch)
    karl2d.play_sound(sound^)
}