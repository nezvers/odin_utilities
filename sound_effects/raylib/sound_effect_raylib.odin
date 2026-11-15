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

// An effect of a SoundBank by id, with the sound to play
PlayBank::proc(bank:^sf.SoundBank, id:sf.SoundId, sound: rl.Sound, time_seconds:f64)->bool {
    volume, pitch, ok := sf.SoundBankTrigger(bank, id, time_seconds)
    if !ok { return false }
    rl.SetSoundVolume(sound, volume)
    rl.SetSoundPitch(sound, pitch)
    rl.PlaySound(sound)
    return true
}
