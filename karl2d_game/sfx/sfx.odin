package sfx

import "../assets"
import "../../karl2d"
import "../../sound_effects"
import snd_glue "../../sound_effects/karl2d"
SfxKarl2D :: snd_glue.SfxKarl2D

settings_gun1: sound_effects.SoundEffect = {
    volume = 0.7,
    pitch_rand_min = 0.9,
    pitch_rand_max = 1.2,
    pitch_min = 0.5,
    pitch_max = 1.75,
    pitch_increment = 0.01,     // Pitch change on fast retrigger
    retrigger_treshold = 0.02,  // Don't play if sooner than this
    retrigger_interval = 0,     // Applay pitch_increment
    pitch_return = 0,           // Return to starting pitch
}

settings_damage: sound_effects.SoundEffect = {
    volume = 0.7,
    pitch_rand_min = 0.9,
    pitch_rand_max = 1.2,
    pitch_min = 0.5,
    pitch_max = 1.75,
    pitch_increment = 0.01,     // Pitch change on fast retrigger
    retrigger_treshold = 0.02,  // Don't play if sooner than this
    retrigger_interval = 0,     // Applay pitch_increment
    pitch_return = 0,           // Return to starting pitch
}

settings_impact: sound_effects.SoundEffect = {
    volume = 1,
    pitch_rand_min = 0.9,
    pitch_rand_max = 1.2,
    pitch_min = 0.5,
    pitch_max = 1.75,
    pitch_increment = 0.01,     // Pitch change on fast retrigger
    retrigger_treshold = 0.02,  // Don't play if sooner than this
    retrigger_interval = 0,     // Applay pitch_increment
    pitch_return = 0,           // Return to starting pitch
}

sound_gun1: karl2d.Sound
sound_damage: karl2d.Sound
sound_impact: karl2d.Sound

gun: SfxKarl2D
damage: SfxKarl2D
impact: SfxKarl2D   // Projectile.sfx_impact

Load :: proc() {
    sound_gun1 = karl2d.load_sound_from_bytes(assets.sound_gun1)
    gun = snd_glue.Init(&settings_gun1, &sound_gun1)

    sound_damage = karl2d.load_sound_from_bytes(assets.sound_damage)
    damage = snd_glue.Init(&settings_damage, &sound_damage)

    sound_impact = karl2d.load_sound_from_bytes(assets.sound_impact)
    impact = snd_glue.Init(&settings_impact, &sound_impact)
}

Destroy :: proc() {
    karl2d.destroy_sound(sound_gun1)
    karl2d.destroy_sound(sound_damage)
    karl2d.destroy_sound(sound_impact)
}

Play :: proc(sound: ^SfxKarl2D) {
    snd_glue.PlaySfxKarl2D(sound, karl2d.get_time())
}