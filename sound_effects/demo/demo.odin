package demo

import rl "vendor:raylib"
import sf ".."
import rs "../raylib"

button_sound:rl.Sound
damage_sound:rl.Sound

button_sfx:sf.SoundEffect = {
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

damage_sfx:sf.SoundEffect = {
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

game_init :: proc() {
    rl.InitAudioDevice()

    button_sound = rl.LoadSound("demo/button_sound.wav")
    damage_sound = rl.LoadSound("demo/damage_sound.wav")

    // Apply volume setting
    rs.Init(&button_sfx, &button_sound)
    rs.Init(&damage_sfx, &damage_sound)
}

game_shutdown :: proc() {
	rl.UnloadSound(button_sound)
	rl.UnloadSound(damage_sound)

    rl.CloseAudioDevice()
}

update :: proc() {

}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)
    
    current_time:f64 = rl.GetTime()
    
    button_rect:rl.Rectangle = {10, 10, 150, 25}
    if rl.GuiButton(button_rect, "Button Sound"){
        rs.Play(&button_sfx, current_time, &button_sound)
    }
    button_rect.y += 30
    if rl.GuiButton(button_rect, "Damage Sound"){
        rs.Play(&damage_sfx, current_time, &damage_sound)
    }

    rl.EndDrawing()
}
