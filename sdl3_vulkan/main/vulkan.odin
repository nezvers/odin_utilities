#+ private file
package main

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:log"
import "core:slice"
import "base:runtime"
import "core:os"

VALIDATION_LAYERS := []cstring{"VK_LAYER_KHRONOS_validation"}
current_frame: int

all_extensions: [dynamic]cstring
instance: vk.Instance
surface: vk.SurfaceKHR
debug_messenger: vk.DebugUtilsMessengerEXT
physical_device: vk.PhysicalDevice
graphics_queue: vk.Queue

graphics_queue_family_index: u32
device: vk.Device
swapchain: SwapchainBundle
render_pass: vk.RenderPass
pipeline: vk.Pipeline
pipeline_layout: vk.PipelineLayout
framebuffers: []vk.Framebuffer
command_pool: vk.CommandPool
command_buffers: []vk.CommandBuffer
sync_objects: SyncObjects

SwapchainBundle :: struct {
	handle:      vk.SwapchainKHR,
	format:      vk.Format,
	extent:      vk.Extent2D,
	images:      []vk.Image,
	image_views: []vk.ImageView,
}

// Sync things (Semaphore and Fence)
MAX_FRAMES_IN_FLIGHT :: 4
SyncObjects :: struct {
	image_available_semaphores: []vk.Semaphore,
	render_finished_semaphores: []vk.Semaphore,
	in_flight_fences:           []vk.Fence,
}

@(private="package") init_vulkan :: proc()->bool {
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

    if !create_instance() { return false }
    if !create_surface() { return false }
    if !create_device() { return false }
    if !create_swapchain() { return false }
    if !create_render_pass() { return false }
    if !create_render_pipeline() { return false }
    if !create_framebuffer() { return false }
    if !create_command_pool() { return false }
    if !create_command_buffers() { return false }
    if !create_sync_objects() { return false }

    log.info("Vulkan Initialized successfully!")
    return true
}

@(private="package") finit_vulkan :: proc() {
    // Wait for GPU to finish before cleaning up
    vk.DeviceWaitIdle(device)

    {
		// Destroy Sync Objects
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			vk.DestroySemaphore(device, sync_objects.render_finished_semaphores[i], nil)
			vk.DestroySemaphore(device, sync_objects.image_available_semaphores[i], nil)
			vk.DestroyFence(device, sync_objects.in_flight_fences[i], nil)
		}
		delete(sync_objects.render_finished_semaphores)
		delete(sync_objects.image_available_semaphores)
		delete(sync_objects.in_flight_fences)

		// Destroy Pipeline
		vk.DestroyPipeline(device, pipeline, nil)
		vk.DestroyPipelineLayout(device, pipeline_layout, nil)

		// Delete command Buffer
		delete(command_buffers)

		// Destroy command Pool
		vk.DestroyCommandPool(device, command_pool, nil)

		// Destroy framebuffers
		for fb in framebuffers {
			vk.DestroyFramebuffer(device, fb, nil)
		}
		delete(framebuffers)

		// Destroy render pass
		vk.DestroyRenderPass(device, render_pass, nil)
		for view in swapchain.image_views {
			vk.DestroyImageView(device, view, nil)
		}
		delete(swapchain.image_views)
		delete(swapchain.images) // Just delete the Odin slice, not the handles (swapchain owns them)
		vk.DestroySwapchainKHR(device, swapchain.handle, nil)
	}

    vk.DestroyDevice(device, nil)
    vk.DestroySurfaceKHR(instance, surface, nil)
    if vk.DestroyDebugUtilsMessengerEXT != nil {
		vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
	}
    vk.DestroyInstance(instance, nil)
    delete(all_extensions)
    sdl.Vulkan_UnloadLibrary()
}

@(private="package") draw_vulkan :: proc() {
    draw_frame(
        device,
        graphics_queue,
        graphics_queue, // We use the same queue for both
        &swapchain,
        &sync_objects,
        command_buffers,
        render_pass,
        framebuffers,
        &current_frame,
        pipeline,
    )
}

create_instance :: proc()->bool {
    // Define the Debug Info (chained to Instance Creation)
	debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.VERBOSE, .WARNING, .ERROR},
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_callback, // Make sure this function exists!
	}

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Odin Vulkan SDL3",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = ENGINE_NAME,
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,

		// Link the Debug Info so we catch creation errors
		pNext                   = &debug_create_info,

		// Use 'all_extensions', not the raw SDL pointer
		enabledExtensionCount   = u32(len(all_extensions)),
		ppEnabledExtensionNames = raw_data(all_extensions),

		// Enable the Validation Layers
		enabledLayerCount       = u32(len(VALIDATION_LAYERS)),
		ppEnabledLayerNames     = raw_data(VALIDATION_LAYERS),
	}

    if res := vk.CreateInstance(&create_info, nil, &instance); res != .SUCCESS {
		log.errorf("Failed to create Vulkan Instance: %v", res)
		return false
	}
    vk.load_proc_addresses(instance)

    // Optional: Create the persistent messenger if you want debugging after instance creation
	// (The pNext above only handles creation-time debugging)
	if vk.CreateDebugUtilsMessengerEXT != nil {
		vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &debug_messenger)
	}
    
    return true
}

create_surface :: proc()->bool {
    if !sdl.Vulkan_CreateSurface(window, instance, nil, &surface) {
		log.errorf("Failed to create Vulkan Surface: %s", sdl.GetError())
		return false
	}
    return true
}

create_device :: proc()->bool {
    // Pick GPU
    ok: bool
	physical_device, ok = pick_physical_device(instance)
	if !ok {
		log.errorf("Failed to find a suitable GPU: %s", sdl.GetError())
		return false
	}

	// print the best gpu that will be selected
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &props)
	log.infof("Selected GPU: %s", props.deviceName)

    // --- Create Logical Device ---
	device_ok: bool
    device, graphics_queue, graphics_queue_family_index, device_ok = init_logical_device( physical_device, surface)
	if !device_ok { return false }

    vk.load_proc_addresses(device)
	log.info("Logical Device Created Successfully!")

    return true
}

create_swapchain :: proc()->bool {
	swapchain_ok: bool

	swapchain, swapchain_ok = init_swapchain(
		physical_device,
		device,
		surface,
		window,
		graphics_queue_family_index,
	)

	if !swapchain_ok { return false }
    return true
}

create_render_pass :: proc()->bool {
    ok:bool
	render_pass, ok = init_render_pass(device, swapchain.format)
	if !ok { return false }
    return true
}

create_render_pipeline :: proc()->bool {
    ok:bool
	pipeline, pipeline_layout, ok = init_graphics_pipeline(device, render_pass)
	if !ok { return false }
    return true
}

create_framebuffer :: proc()->bool {
    ok:bool
	framebuffers, ok = init_framebuffers(device, render_pass, &swapchain)
	if !ok { return false }
    return true
}

create_command_pool :: proc()->bool {
    ok:bool
	command_pool, ok = init_command_pool(device, graphics_queue_family_index)
	if !ok { return false }
    return true
}

create_command_buffers :: proc()->bool {
    ok:bool
	command_buffers, ok = init_command_buffers(device, command_pool, u32(len(framebuffers)))
	if !ok { return false }
    return true
}

create_sync_objects :: proc()->bool {
    ok:bool
	sync_objects, ok = init_sync_objects(device)
	if !ok { return false }
    return true
}

// --- CALLBACK FUNCTION ---
debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {

	context = runtime.default_context()

	if .ERROR in messageSeverity {
		log.errorf("[VK ERROR] %s\n", pCallbackData.pMessage)
	} else if .WARNING in messageSeverity {
		log.errorf("[VK WARN]  %s\n", pCallbackData.pMessage)
	}

	return false
}

pick_physical_device :: proc(instance: vk.Instance) -> (vk.PhysicalDevice, bool) {
	// check how many gpu is there
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		return nil, false
	}

	// get the actual device
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))


	// check them then pick the best one
	best_device: vk.PhysicalDevice
	best_score := -1

	for device in devices {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)

		score := 0

		// Discrete GPUs (Dedicated cards like NVIDIA/AMD) are usually better
		if props.deviceType == .DISCRETE_GPU {
			score += 1000
		}
		// Integrated GPUs (Intel HD/Iris, AMD APU)
		if props.deviceType == .INTEGRATED_GPU {
			score += 100
		}

		// Maximum texture size is a decent tie-breaker
		score += int(props.limits.maxImageDimension2D)

		log.infof("Found GPU: %s (Score: %d)", props.deviceName, score)

		if score > best_score {
			best_device = device
			best_score = score
		}
	}

	if best_score > 0 {
		return best_device, true
	}

	return nil, false
}

init_logical_device :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (vk.Device,vk.Queue,u32,bool) {
	// find Queues Family
	queue_family_count: u32

	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_family_count,
		raw_data(queue_families),
	)

	graphics_family_index := -1

	//
	for family, i in queue_families {
		// Check for Graphics support
		if .GRAPHICS in family.queueFlags {
			// Check for Presentation support
			present_support: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(
				physical_device,
				u32(i),
				surface,
				&present_support,
			)

			if present_support {
				graphics_family_index = i
				break
			}
		}
	}

	if graphics_family_index == -1 {
		log.error("Failed to find a Queue Family that supports both Graphics and Presentation")
		return nil, nil, 0, false
	}

	log.infof("Using Queue Family Index: %d", graphics_family_index)

	// prepare Queue Creation info
	queue_priority: f32 = 1.0

	queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = u32(graphics_family_index),
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	// Required device extensions
	device_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	// create logical device
	device_features := vk.PhysicalDeviceFeatures{} // TODO: enabling features here later

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = 1,
		pQueueCreateInfos       = &queue_create_info,
		pEnabledFeatures        = &device_features,
		enabledExtensionCount   = u32(len(device_extensions)),
		ppEnabledExtensionNames = raw_data(device_extensions),
	}

	_device: vk.Device
	if res := vk.CreateDevice(physical_device, &create_info, nil, &_device); res != .SUCCESS {
		log.errorf("Failed to create Logical Device: %v", res)
		return nil, nil, 0, false
	}

	// retrieve queue handle
	_graphics_queue: vk.Queue
	vk.GetDeviceQueue(_device, u32(graphics_family_index), 0, &_graphics_queue)
	return _device, _graphics_queue, u32(graphics_family_index), true

}

init_swapchain :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	surface: vk.SurfaceKHR,
	window: ^sdl.Window,
	graphics_family_index: u32,
) -> (
	SwapchainBundle,
	bool,
) {
	bundle: SwapchainBundle

	// Queries surface Capabilities
	capabilities: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities)

	// Choose the resolution
	if capabilities.currentExtent.width != max(u32) {
		bundle.extent = capabilities.currentExtent
	} else {
		w, h: i32
		sdl.GetWindowSizeInPixels(window, &w, &h)
		bundle.extent.width = u32(w)
		bundle.extent.height = u32(h)

		// clamp to min/max allowed by the GPU
		bundle.extent.width = clamp(
			bundle.extent.width,
			capabilities.minImageExtent.width,
			capabilities.maxImageExtent.width,
		)
		bundle.extent.height = clamp(
			bundle.extent.height,
			capabilities.minImageExtent.height,
			capabilities.maxImageExtent.height,
		)
	}

	// Choose surface format (Color Space)
	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nil)
	formats := make([]vk.SurfaceFormatKHR, format_count)
	defer delete(formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&format_count,
		raw_data(formats),
	)

	// Default fallback
	bundle.format = formats[0].format
	color_space := formats[0].colorSpace

	for f in formats {
		// Prefer standard SRGB (standard monitor colors)
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			bundle.format = f.format
			color_space = f.colorSpace
			break
		}
	}


	// choose present mode
	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, nil)
	present_modes := make([]vk.PresentModeKHR, present_mode_count)
	defer delete(present_modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&present_mode_count,
		raw_data(present_modes),
	)

	// FIFO is guaranteed to exist (this is standard V-Sync)
	present_mode := vk.PresentModeKHR.FIFO

	// for mode in present_modes {
	// 	// MAILBOX is "Triple Buffering". It allows unlimited FPS without screen tearing.
	// 	if mode == .MAILBOX {
	// 		present_mode = .MAILBOX
	// 		break
	// 	}
	// }

	// Image count
	// Triple buffering needs 3 images
	image_count := capabilities.minImageCount + 1
	if capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount {
		image_count = capabilities.maxImageCount
	}

	// create the Swapchain
	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = image_count,
		imageFormat      = bundle.format,
		imageColorSpace  = color_space,
		imageExtent      = bundle.extent,
		imageArrayLayers = 1, // Always 1 unless doing VR/Stereo 3D
		imageUsage       = {.COLOR_ATTACHMENT}, // We will draw color to these images
		preTransform     = capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true, // Don't calculate pixels covered by other windows
		oldSwapchain     = {}, // Used when resizing window later
	}

	// Explicitly state using one queue for both Graphics and Present
	create_info.imageSharingMode = .EXCLUSIVE

	if res := vk.CreateSwapchainKHR(device, &create_info, nil, &bundle.handle); res != .SUCCESS {
		log.errorf("Failed to create Swapchain: %v", res)
		return bundle, false
	}

	// Retrive Images and Create Views
	vk.GetSwapchainImagesKHR(device, bundle.handle, &image_count, nil)
	bundle.images = make([]vk.Image, image_count)
	vk.GetSwapchainImagesKHR(device, bundle.handle, &image_count, raw_data(bundle.images))

	bundle.image_views = make([]vk.ImageView, image_count)

	for i in 0 ..< image_count {
		view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = bundle.images[i],
			viewType = .D2, // It's a 2D image
			format = bundle.format,
			components = { 	// Default mapping (R->R, G->G, etc)
				r = .IDENTITY,
				g = .IDENTITY,
				b = .IDENTITY,
				a = .IDENTITY,
			},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		if res := vk.CreateImageView(device, &view_info, nil, &bundle.image_views[i]);
		   res != .SUCCESS {
			log.errorf("Failed to create Swapchain Image View: %v", res)
			return bundle, false
		}
	}

	log.infof(
		"Swapchain Created! Size: %dx%d | Mode: %v | Images: %d",
		bundle.extent.width,
		bundle.extent.height,
		present_mode,
		len(bundle.images),
	)

	return bundle, true
}

init_render_pass :: proc(
	device: vk.Device,
	swapchain_format: vk.Format,
) -> (
	vk.RenderPass,
	bool,
) {
	color_attachment := vk.AttachmentDescription {
		format         = swapchain_format,
		samples        = {._1},

		// like gl Clear
		loadOp         = .CLEAR,

		// save the result
		storeOp        = .STORE,

		// Stecil not used right now
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,

		// Layout Transition
		initialLayout  = .UNDEFINED,

		// final Layout
		finalLayout    = .PRESENT_SRC_KHR,
	}

	// Subpass references
	color_attachment_ref := vk.AttachmentReference {
		attachment = 0, // index in the pAttachment array below
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	// subpass description
	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_ref,
	}

	// Subpass Dependecy
	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,

		// wait for color attachment
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	// Create the Render Pass
	render_pass_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	_render_pass: vk.RenderPass
	if res := vk.CreateRenderPass(device, &render_pass_info, nil, &_render_pass); res != .SUCCESS {
		log.errorf("Failed to create Render Pass: %v", res)
		return {}, false
	}

	log.info("Render Pass Created Successfully")
	return _render_pass, true
}

init_graphics_pipeline :: proc(
	device: vk.Device,
	render_pass: vk.RenderPass,
) -> (
	vk.Pipeline,
	vk.PipelineLayout,
	bool,
) {
	// Load Shader Modules
	vert_module, v_ok := load_shader_module(device, "shaders/vert.spv")
	frag_module, f_ok := load_shader_module(device, "shaders/frag.spv")

	if !v_ok || !f_ok {
		return {}, {}, false
	}

	defer vk.DestroyShaderModule(device, vert_module, nil)
	defer vk.DestroyShaderModule(device, frag_module, nil)

	// Shader Stages Creation Info
	vert_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vert_module,
		pName  = "main", // The entry point function name in GLSL
	}

	frag_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = frag_module,
		pName  = "main",
	}

	shader_stages := []vk.PipelineShaderStageCreateInfo{vert_stage_info, frag_stage_info}

	// Vertex Input (Empty for now because hardcoded points in the shader)
	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 0,
		vertexAttributeDescriptionCount = 0,
	}

	// Input Assembly (Triangles)
	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST, // Every 3 vertices = 1 triangle
		primitiveRestartEnable = false,
	}

	// Dynamic States
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// Viewport & Scissor (Values don't matter much here since they are Dynamic)
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	// Rasterizer (Fill mode, Culling)
	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL, // Fill the triangle with color
		lineWidth               = 1.0,
		cullMode                = {.BACK}, // Don't draw the back of the triangle
		frontFace               = .CLOCKWISE,
		depthBiasEnable         = false,
	}

	// Multisampling (Disabled for now)
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	// Color Blending (Standard mixing)
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false, // Set to true for transparency
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	// Pipeline Layout (Global variables/Uniforms)
	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}

	_pipeline_layout: vk.PipelineLayout
	if res := vk.CreatePipelineLayout(device, &pipeline_layout_info, nil, &_pipeline_layout);
	   res != .SUCCESS {
		log.errorf("Failed to create pipeline layout: %v", res)
		return {}, {}, false
	}

	// Create the Actual Pipeline
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state_info,
		layout              = _pipeline_layout,
		renderPass          = render_pass,
		subpass             = 0,
	}

	_pipeline: vk.Pipeline
	if res := vk.CreateGraphicsPipelines(device, {}, 1, &pipeline_info, nil, &_pipeline);
	   res != .SUCCESS {
		log.errorf("Failed to create graphics pipeline: %v", res)
		return {}, {}, false
	}

	log.info("Graphics Pipeline Created Successfully!")
	return _pipeline, _pipeline_layout, true
}

load_shader_module :: proc(device: vk.Device, filename: string) -> (vk.ShaderModule, bool) {
	// Read the binary file
	code, err := os.read_entire_file(filename, context.allocator)
	if err != nil {
		log.errorf("Failed to read shader file: %s", filename)
		return {}, false
	}
	defer delete(code) // Free the file memory after we upload it to Vulkan

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}

	module: vk.ShaderModule
	if res := vk.CreateShaderModule(device, &create_info, nil, &module); res != .SUCCESS {
		log.errorf("Failed to create shader module for %s: %v", filename, res)
		return {}, false
	}

	return module, true
}

init_framebuffers :: proc(
	device: vk.Device,
	render_pass: vk.RenderPass,
	swapchain: ^SwapchainBundle,
) -> (
	[]vk.Framebuffer,
	bool,
) {
	buffers := make([]vk.Framebuffer, len(swapchain.image_views))

	for i in 0 ..< len(swapchain.image_views) {
		// specific attachment for this framebuffer
		attachments := []vk.ImageView{swapchain.image_views[i]}

		framebuffers_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments),

			// dimension
			width           = swapchain.extent.width,
			height          = swapchain.extent.height,
			layers          = 1,
		}

		if res := vk.CreateFramebuffer(device, &framebuffers_info, nil, &buffers[i]);
		   res != .SUCCESS {
			log.errorf("Failed to create Framebuffer %d: %v", i, res)
			// If one fails, we should probably cleanup what we made,
			// but for simplicity here we just return failure.
			return nil, false
		}
	}


	log.infof("Created %d Framebuffers", len(buffers))
	return buffers, true
}

init_command_pool :: proc(device: vk.Device, queue_family_index: u32) -> (vk.CommandPool, bool) {
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = queue_family_index,
		// allow to re-record buffers individually
		flags            = {.RESET_COMMAND_BUFFER},
	}
	pool: vk.CommandPool
	if res := vk.CreateCommandPool(device, &pool_info, nil, &pool); res != .SUCCESS {
		log.errorf("Failed to create Command Pool: %v", res)
		return {}, false
	}

	log.info("Command Pool Created Successfully")
	return pool, true
}

init_command_buffers :: proc(
	device: vk.Device,
	pool: vk.CommandPool,
	count: u32,
) -> (
	[]vk.CommandBuffer,
	bool,
) {
	buffers := make([]vk.CommandBuffer, count)

	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool,
		commandBufferCount = count,
		level              = .PRIMARY, // Can be submitted to a queue directly
	}

	if res := vk.AllocateCommandBuffers(device, &alloc_info, raw_data(buffers)); res != .SUCCESS {
		log.errorf("Failed to create Command Buffers: %v", res)
		delete(buffers)
		return {}, false
	}

	log.infof("Allocated %d Command Buffers", count)
	return buffers, true
}

init_sync_objects :: proc(device: vk.Device) -> (SyncObjects, bool) {
	sync: SyncObjects

	// Resize Array to match frames in Flight
	sync.image_available_semaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	sync.render_finished_semaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	sync.in_flight_fences = make([]vk.Fence, MAX_FRAMES_IN_FLIGHT)

	// Info for creating semaphore (just basic things)
	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	// Info for creating Fence
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,

		// CRITICAL: Create them in the SIGNALED state.
		// If we don't, the very first loop will wait forever for a "previous frame"
		// that never existed.
		flags = {.SIGNALED},
	}

	// error checking
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if vk.CreateSemaphore(device, &semaphore_info, nil, &sync.image_available_semaphores[i]) !=
			   .SUCCESS ||
		   vk.CreateSemaphore(device, &semaphore_info, nil, &sync.render_finished_semaphores[i]) !=
			   .SUCCESS ||
		   vk.CreateFence(device, &fence_info, nil, &sync.in_flight_fences[i]) != .SUCCESS {

			log.error("Failed to create synchronization objects for a frame!")
			return sync, false
		}
	}

	log.infof("Synchronization Objects Created Successfully")
	return sync, true
}

draw_frame :: proc(
	device: vk.Device,
	graphics_queue: vk.Queue,
	present_queue: vk.Queue, // this is the same as graphics_queue
	swapchain: ^SwapchainBundle,
	sync: ^SyncObjects,
	command_buffers: []vk.CommandBuffer,
	render_pass: vk.RenderPass,
	framebuffers: []vk.Framebuffer,
	current_frame: ^int,
	pipeline: vk.Pipeline,
) {
	// wait previous frame to finish
	vk.WaitForFences(device, 1, &sync.in_flight_fences[current_frame^], true, max(u64))

	// Acquire an Image from the swapchain
	image_index: u32
	result :vk.Result
    result = vk.AcquireNextImageKHR(
		device,
		swapchain.handle,
		max(u64),
		sync.image_available_semaphores[current_frame^],
		{},
		&image_index,
	)

	// Handle window resizing (OUT_OF_DATE) later. For now, just exit if failed.
	// if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
	// 	log.error("Failed to acquire swapchain image!")
	// 	return
	// }
	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
		return
	} else if result != .SUCCESS {
		log.error("Failed to acquire swapchain image!")
		return
	}


	// Reset the Fence
	// Only reset AFTER sure submitting work, otherwise might deadlock.
	result = vk.ResetFences(device, 1, &sync.in_flight_fences[current_frame^])

	// record the command buffers
    result = vk.ResetCommandBuffer(command_buffers[current_frame^], {})
    if result != .SUCCESS {
        log.error("Failed to ResetCommandBuffer")
    }

	record_command_buffer(
		command_buffers[current_frame^],
		image_index,
		render_pass,
		framebuffers,
		swapchain.extent,
		pipeline,
	)

	// Submit command buffer
	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
	}

	// Wait for the image to be available before writing colors
	wait_semaphores := []vk.Semaphore{sync.image_available_semaphores[current_frame^]}
	wait_stages := []vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	submit_info.waitSemaphoreCount = 1
	submit_info.pWaitSemaphores = raw_data(wait_semaphores)
	submit_info.pWaitDstStageMask = raw_data(wait_stages)

	// Which buffer to execute
	cmd_bufs := []vk.CommandBuffer{command_buffers[current_frame^]}
	submit_info.commandBufferCount = 1
	submit_info.pCommandBuffers = raw_data(cmd_bufs)

	// Signal this semaphore when drawing is done
	signal_semaphores := []vk.Semaphore{sync.render_finished_semaphores[current_frame^]}
	submit_info.signalSemaphoreCount = 1
	submit_info.pSignalSemaphores = raw_data(signal_semaphores)

	// Submit! (And signal the Fence when the GPU is totally done)
    result = vk.QueueSubmit(graphics_queue, 1, &submit_info, sync.in_flight_fences[current_frame^])
	if result != .SUCCESS {
		log.error("Failed to submit draw command buffer!")
		return
	}

	// Present the image to the screen
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = raw_data(signal_semaphores), // Wait for drawing to finish
		swapchainCount     = 1,
		pSwapchains        = &swapchain.handle,
		pImageIndices      = &image_index,
	}

	result = vk.QueuePresentKHR(present_queue, &present_info)

	// Advance to the next frame (0 -> 1 -> 0 -> 1...)
	current_frame^ = (current_frame^ + 1) % MAX_FRAMES_IN_FLIGHT
}

record_command_buffer :: proc(
	buffer: vk.CommandBuffer,
	image_index: u32,
	render_pass: vk.RenderPass,
	framebuffers: []vk.Framebuffer,
	extent: vk.Extent2D,
	pipeline: vk.Pipeline,
) {
	// Begin Recording
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {}, // Optional
	}

	if vk.BeginCommandBuffer(buffer, &begin_info) != .SUCCESS {
		log.errorf("Failed to begin recording command buffer!")
		return
	}

	// Define the clear color
	clear_color := vk.ClearValue{}
	clear_color.color.float32 = {0.5, 0.0, 0.5, 1.0}

	// start render pass
	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = render_pass,
		framebuffer = framebuffers[image_index],
		renderArea = {offset = {0.0, 0.0}, extent = extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}

	vk.CmdBeginRenderPass(buffer, &render_pass_info, .INLINE)

	// Drawing commands go here

	// vk.CmdBindPipeline(...)
	// vk.CmdDraw(...)

	// Bind the pipeline
	vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline)

	// set dynamic viewport
	viewport := vk.Viewport {
		x        = 0.0,
		y        = 0.0,
		width    = f32(extent.width),
		height   = f32(extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(buffer, 0, 1, &viewport)

	// set the scissor
	scissor := vk.Rect2D {
		offset = {0.0, 0.0},
		extent = extent,
	}
	vk.CmdSetScissor(buffer, 0, 1, &scissor)

	// Draw Triangle
	vk.CmdDraw(buffer, 3, 1, 0, 0)


	// End Drawing
	vk.CmdEndRenderPass(buffer)
	if vk.EndCommandBuffer(buffer) != .SUCCESS {
		log.error("Failed to record command buffers!")
	}

}