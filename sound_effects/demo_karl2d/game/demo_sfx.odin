#+private file
package game

// import "core:fmt"
import "../../../karl2d"

import sfx "../.."
import glue "../../karl2d"
SfxKarl2D :: glue.SfxKarl2D

import "core:math"
PI :: math.PI

@(private="package")
sfx_state: GameState = {
    init,
    finit,
    process,
    draw,
}

button_clip: karl2d.Audio_Clip
damage_clip: karl2d.Audio_Clip

button_sfx: sfx.SoundEffect = {
    volume = 1,
    pitch_rand_min = 0.9,
    pitch_rand_max = 1.2,
    pitch_min = 0.5,
    pitch_max = 1.75,
    pitch_increment = 0.01,     // Pitch change on fast retrigger
    retrigger_treshold = 0.02,  // Don't play if sooner than this
    retrigger_interval = 0.5,   // Applay pitch_increment
    pitch_return = 1,           // Return to starting pitch
}

damage_sfx: sfx.SoundEffect = {
    volume = 0.5,
    pitch_rand_min = 0.9,
    pitch_rand_max = 1.2,
    pitch_min = 0.5,
    pitch_max = 1.75,
    pitch_increment = 0.01,
    retrigger_treshold = 0.02,
    retrigger_interval = 0.5,
    pitch_return = 1,
}

button_sfx_karl2d: SfxKarl2D
damage_sfx_karl2d: SfxKarl2D

init :: proc() {
    background_color = karl2d.WHITE

    button_clip = karl2d.load_audio_clip_from_bytes(#load("../../../assets/sounds/button_sound.wav"))
    damage_clip = karl2d.load_audio_clip_from_bytes(#load("../../../assets/sounds/damage_sound.wav"))

    // Apply volume setting
    button_sfx_karl2d = glue.Init(&button_sfx, &button_clip)
    damage_sfx_karl2d = glue.Init(&damage_sfx, &damage_clip)
}

finit :: proc() {
    karl2d.destroy_audio_clip(button_clip)
    karl2d.destroy_audio_clip(damage_clip)
}

process :: proc() {
    
}

draw :: proc() {
    FONT_SIZE :: 20
	BUTTON_SIZE :Vec2: {150, 25}
	BUTTON_PADDING :f32: 2
    mouse_position: = get_local_mouse_position()
    current_time: f64 = karl2d.get_time()
    button_rect: Rect = {10, 10, BUTTON_SIZE.x, BUTTON_SIZE.y}

    karl2d.draw_rect(button_rect, karl2d.LIGHT_GRAY)
    karl2d.draw_text("Button", {button_rect.x + 5, button_rect.y + 3}, FONT_SIZE, karl2d.BLACK)
    if (check_hover(mouse_position, button_rect)){
        if karl2d.mouse_button_went_down(.Left) {
            glue.PlaySfxKarl2D(&button_sfx_karl2d, current_time)
        }
    }
    button_rect.y += BUTTON_SIZE.y + 5

    karl2d.draw_rect(button_rect, karl2d.LIGHT_GRAY)
    karl2d.draw_text("Damage", {button_rect.x + 5, button_rect.y + 3}, FONT_SIZE, karl2d.BLACK)
    if (check_hover(mouse_position, button_rect)){
        if karl2d.mouse_button_went_down(.Left) {
            glue.PlaySfxKarl2D(&damage_sfx_karl2d, current_time)
        }
    }
}