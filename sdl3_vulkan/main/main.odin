package main

// IMPORTANT: SDL3.dll must be next to executable or in PATH
import sdl "vendor:sdl3"
import "core:log"
// import "core:fmt"
import "core:strings"
import "core:mem"

WIDTH :: 640
HEIGHT :: 480

current_surface : ^sdl.Surface
screen_surface : ^sdl.Surface
stretched_surface : ^sdl.Surface
window : ^sdl.Window

main :: proc() {
    // LOG
    cl := log.create_console_logger()
	context.logger = cl

    // ALLOCATOR
    tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer reset_tracking_allocator()

    // INIT
    if !init() {
        return
	}
    defer exit()

    format_details := sdl.GetPixelFormatDetails(screen_surface.format)
    sdl.FillSurfaceRect(screen_surface, nil, sdl.MapRGB(format_details, nil, 0xFF, 0xFF, 0xFF)) // Fill with white

    quit: bool
    e: sdl.Event
    for !quit {
        for sdl.PollEvent(&e) {
            if e.type == sdl.EventType.QUIT {
                quit = true
            }
        }  
        // sdl.BlitSurfaceScaled(stretched_surface, nil, screen_surface, &stretch_rect, sdl.ScaleMode.LINEAR)
        sdl.UpdateWindowSurface(window)
    }
}

reset_tracking_allocator :: proc() -> bool {
	a := cast(^mem.Tracking_Allocator)context.allocator.data
	err := false
	if len(a.allocation_map) > 0 {
		log.warnf("Leaked allocation count: %v", len(a.allocation_map))
	}
	for _, v in a.allocation_map {
		log.warnf("%v: Leaked %v bytes", v.location, v.size)
		err = true
	}

	mem.tracking_allocator_clear(a)
	return err
}

load_surface :: proc(path : string) -> ^sdl.Surface {
    bmp := sdl.LoadBMP(strings.clone_to_cstring(path))
    if bmp == nil {
        log.fatalf("Unable to load image %s! SDL error: %s", bmp, sdl.GetError())
        return bmp
    }
    surf := sdl.ConvertSurface(bmp, screen_surface.format)
    if surf == nil {
        log.fatalf("Unable to optimise image %s! SDL error: %s", surf, sdl.GetError())
        return surf
    }
    sdl.DestroySurface(bmp)

    return surf
}

init :: proc() -> bool {
    if !sdl.Init(sdl.InitFlags{.VIDEO}) {
        log.fatalf("SDL could not init! SDL_Error: %s", sdl.GetError())
        return false
    }
    window = sdl.CreateWindow(
        "Optimised Surface Loading and Soft Stretching",
        WIDTH, HEIGHT,
        {sdl.WindowFlags.RESIZABLE},
    )
    if window == nil {
        log.fatalf("Could not create window. SDL_Error: %s", sdl.GetError())
        return false
    }
    screen_surface = sdl.GetWindowSurface(window)
    return true
}

exit :: proc() {
    sdl.DestroyWindow(window)
    sdl.DestroySurface(stretched_surface)
    sdl.Quit()
}