package sound_effect_karl2d

import sfx ".."
import "../../karl2d"

SfxKarl2D :: struct {
    sound_effect:^sfx.SoundEffect,
    clip: ^karl2d.Audio_Clip,
}

Init :: proc(sound_effect:^sfx.SoundEffect, clip: ^karl2d.Audio_Clip)->SfxKarl2D {
    return {sound_effect, clip}
}

PlaySfxKarl2D :: proc(sound_effect: ^SfxKarl2D, time_seconds:f64) {
    assert(sound_effect != nil)
    Play(sound_effect.sound_effect, time_seconds, sound_effect.clip)
}

// Fire-and-forget, each call starts a new voice with current volume and pitch
Play :: proc(sound_effect:^sfx.SoundEffect, time_seconds:f64, clip: ^karl2d.Audio_Clip){
    assert(sound_effect != nil)
    if !sfx.Play(sound_effect, time_seconds){
        return
    }

    karl2d.play_audio_clip(clip^, sound_effect.volume, 0, sound_effect.pitch)
}

// An effect of a SoundBank by id, with the clip to play. Nothing plays when the effect says it is too soon, or when `clip` is
// empty (not loaded yet): the retrigger state only moves for a sound that really plays
PlayBank :: proc(bank:^sfx.SoundBank, id:sfx.SoundId, clip: karl2d.Audio_Clip, time_seconds:f64) -> bool {
    if clip == karl2d.AUDIO_CLIP_NONE { return false }
    volume, pitch, ok := sfx.SoundBankTrigger(bank, id, time_seconds)
    if !ok { return false }
    karl2d.play_audio_clip(clip, volume, 0, pitch)
    return true
}
