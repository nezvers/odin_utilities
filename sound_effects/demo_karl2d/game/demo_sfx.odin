#+private file
package game

// import "core:fmt"
import "../../../karl2d"

import sfx "../.."
import glue "../../karl2d"

import "core:math"
PI :: math.PI

@(private="package")
sfx_state: GameState = {
    init,
    finit,
    process,
    draw,
}

button_sound: karl2d.Sound
damage_sound: karl2d.Sound

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

init :: proc() {
    background_color = karl2d.WHITE

    button_sound = karl2d.load_sound_from_bytes(#load("../../../assets/sounds/button_sound.wav"))
    damage_sound = karl2d.load_sound_from_bytes(#load("../../../assets/sounds/damage_sound.wav"))

    // Apply volume setting
    glue.Init(&button_sfx, &button_sound)
    glue.Init(&damage_sfx, &damage_sound)
}

finit :: proc() {
    karl2d.destroy_sound(button_sound)
    karl2d.destroy_sound(damage_sound)
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
            glue.Play(&button_sfx, current_time, &button_sound)
        }
    }
    button_rect.y += button_rect.y + 5

    karl2d.draw_rect(button_rect, karl2d.LIGHT_GRAY)
    karl2d.draw_text("Damage", {button_rect.x + 5, button_rect.y + 3}, FONT_SIZE, karl2d.BLACK)
    if (check_hover(mouse_position, button_rect)){
        if karl2d.mouse_button_went_down(.Left) {
            glue.Play(&button_sfx, current_time, &button_sound)
        }
    }
}