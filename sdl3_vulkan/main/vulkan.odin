package main

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:log"
import "core:slice"

all_extensions: [dynamic]cstring

init_vulkan :: proc()->bool {
    if !sdl.Vulkan_LoadLibrary(nil) {
		log.errorf("Failed to load Vulkan Library: %s", sdl.GetError())
		return false
	}
    vk.load_proc_addresses_global(cast(rawptr)sdl.Vulkan_GetVkGetInstanceProcAddr())

    sdl_ext_count: u32
	sdl_ext_ptr := sdl.Vulkan_GetInstanceExtensions(&sdl_ext_count)
	if sdl_ext_ptr == nil {
		log.errorf("Failed to get SDL Vulkan extensions: %s", sdl.GetError())
		return false
	}

    sdl_extensions := slice.from_ptr(sdl_ext_ptr, int(sdl_ext_count))
    // Create new list: SDL Extensions + Debug Extension
	all_extensions = make([dynamic]cstring)
    append(&all_extensions, ..sdl_extensions)
	append(&all_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    log.infof("VULKAN: Enabled Extensions: %v", all_extensions)

    return true
}

finit_vulkan :: proc() {
    delete(all_extensions)
    sdl.Vulkan_UnloadLibrary()
}