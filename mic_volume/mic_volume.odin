package mic_volume

import ma "vendor:miniaudio"

MicContext :: struct {
    ma_ctx: ma.context_type,
    device: ma.device,
    config: ma.device_config,
    playback_info: [^]ma.device_info,
    capture_info: [^]ma.device_info,
    playback_count: u32,
    capture_count: u32,
    // Peak meter
    peak: f32,
    peak_drop_speed: f32,
}

Init :: proc(ctx: ^MicContext, peak_drop_speed:f32 = 1)->(ok:bool) {
    ctx^ = {
        peak_drop_speed = peak_drop_speed,
    }
    if ma.context_init(nil, 0, nil, &ctx.ma_ctx) != ma.result.SUCCESS {
        ok = false
        return
    }
    
    ctx.config = ma.device_config_init(.capture)
    ctx.config.capture.format = .f32    // Set to .unknown to use the device's native format.
    ctx.config.capture.channels = 0     // Set to 0 to use the device's native channel count.
    ctx.config.sampleRate = 0           // Set to 0 to use the device's native sample rate.
    ctx.config.dataCallback = DataCallback // This function will be called when miniaudio needs more data.
    ctx.config.pUserData = cast(rawptr)ctx // Bind reference to be used in data_callback

    // TODO: Refresh device info for added devices
    if !UpdateDeviceInfo(ctx){
        return
    }
    if !SetDevice(ctx, 0){
        return
    }

    ok = true
    return
}

Finit :: proc(ctx: ^MicContext) {
    ma.device_uninit(&ctx.device)
    ma.context_uninit(&ctx.ma_ctx)
}

UpdateDeviceInfo :: proc(ctx: ^MicContext)->bool {
    if ma.context_get_devices(&ctx.ma_ctx, &ctx.playback_info, &ctx.playback_count, &ctx.capture_info, &ctx.capture_count) != ma.result.SUCCESS {
        return false
    }
    return true
}

DataCallback :: proc "c" (device: ^ma.device, output: rawptr, input: rawptr, frame_count: u32) {
    ctx: ^MicContext = cast(^MicContext)device.pUserData // Access context reference
	sample_rate:u32 = device.sampleRate
    channels:u32 = device.capture.channels
    sample_count:u32 = frame_count * channels
    delta_time:f32 = 1 / cast(f32)sample_rate
    drop_amount:f32 = ctx.peak_drop_speed * delta_time
    samples:[^]f32 = cast([^]f32)input
    s: u32
    ch: u32
    sample: f32
    max_sample: f32
    for ;s < sample_count; s += 1 {
        ch = 0
        max_sample = 0
        for ;ch < channels; ch += 1 {
            sample = samples[s]
            if (sample < 0) { sample *= -1 }
            if (max_sample < sample) { max_sample = sample}
        }
        if (ctx.peak < max_sample) { ctx.peak = max_sample }
        else if (ctx.peak > drop_amount) {ctx.peak -= drop_amount}
        else { ctx.peak = 0 }
    }
}

GetDeviceCount :: proc(ctx: ^MicContext)->u32 {
    return ctx.capture_count
}

GetPeak :: proc(ctx: ^MicContext)->f32 {
    return ctx.peak
}

GetDeviceName :: proc(ctx: ^MicContext, idx:u32)-> cstring {
    if (ctx.capture_count < 1) { return {} }
    if (idx >= ctx.capture_count) { return {} }
    result:cstring = cast(cstring)&ctx.capture_info[idx].name[0]
    return result
}

SetDevice :: proc(ctx: ^MicContext, idx:u32)->bool {
    if (ctx.capture_count < 1) { return false}
    if (idx >= ctx.capture_count) { return false }
    ma.device_uninit(&ctx.device)
    ctx.config.capture.pDeviceID = &ctx.capture_info[idx].id

    if (ma.device_init(&ctx.ma_ctx, &ctx.config, &ctx.device) != ma.result.SUCCESS) {
        return false
    }
    if ma.device_start(&ctx.device) != ma.result.SUCCESS {
        ma.device_uninit(&ctx.device)
        return false
    }
    return true
}

SetPeakDropSpeed :: proc(ctx: ^MicContext, value:f32) {
    ctx.peak_drop_speed = value
}