package main

// IMPORTANT: SDL3.dll must be next to executable or in PATH
import sdl "vendor:sdl3"
import "core:strings"
import "core:log"
// import "core:fmt"

// current_surface : ^sdl.Surface
screen_surface : ^sdl.Surface
window : ^sdl.Window
should_close:bool

init_sdl3 :: proc() -> bool {
    if !sdl.Init(sdl.InitFlags{.VIDEO}) {
        log.fatalf("SDL could not init! SDL_Error: %s", sdl.GetError())
        return false
    }
    window = sdl.CreateWindow(
        TITLE,
        WIDTH, HEIGHT,
        {sdl.WindowFlags.RESIZABLE},
    )
    if window == nil {
        log.fatalf("Could not create window. SDL_Error: %s", sdl.GetError())
        return false
    }

    screen_surface = sdl.GetWindowSurface(window)
    format_details := sdl.GetPixelFormatDetails(screen_surface.format)
    sdl.FillSurfaceRect(screen_surface, nil, sdl.MapRGB(format_details, nil, 0xFF, 0xFF, 0xFF)) // Fill with white
    return true
}

finit_sdl3 :: proc() {
    sdl.DestroyWindow(window)
    // sdl.DestroySurface(stretched_surface)
    sdl.Quit()
}

update_input_sdl3 :: proc() {
    e: sdl.Event
    for sdl.PollEvent(&e) {
        if e.type == sdl.EventType.QUIT {
            should_close = true
        }
    }
}

draw_sdl3 :: proc() {
    // sdl.BlitSurfaceScaled(stretched_surface, nil, screen_surface, &stretch_rect, sdl.ScaleMode.LINEAR)
    sdl.UpdateWindowSurface(window)
}

load_surface :: proc(path : string) -> ^sdl.Surface {
    bmp := sdl.LoadBMP(strings.clone_to_cstring(path))
    if bmp == nil {
        log.fatalf("Unable to load image %s! SDL error: %s", bmp, sdl.GetError())
        return nil
    }
    surf := sdl.ConvertSurface(bmp, screen_surface.format)
    if surf == nil {
        log.fatalf("Unable to optimise image %s! SDL error: %s", surf, sdl.GetError())
        return nil
    }
    sdl.DestroySurface(bmp)

    return surf
}