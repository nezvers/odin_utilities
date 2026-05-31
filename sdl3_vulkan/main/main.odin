package main

// IMPORTANT: SDL3.dll must be next to executable
// Reference: www.youtube.com/watch?v=DC9FBRQKNck + https://github.com/nickenchev/modern-vulkan
// Reference: https://github.com/algo-boyz/odins-sdl3/tree/master
// Reference: https://github.com/SiputBiru/sdl3-vulkan-odin

// import "core:fmt"
import "core:log"
import "core:mem"
// import "core:math/linalg"
// import glm "core:math/linalg/glsl"

// used in sdl3.odin
TITLE: cstring : "Odin + Vulkan + SDL3"
window_width: i32 = 640
window_height: i32 =  480


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
    if !init() { return }
    defer exit()

    for !should_close {
        update_events_sdl3()
        draw_sdl3()
    }
}

init :: proc() -> bool {
    if !init_sdl3() { return false }
    if !init_vulkan() { return false }
    return true
}

exit :: proc() {
    finit_sdl3()
    finit_vulkan()
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