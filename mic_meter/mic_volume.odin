package mic_volume

import ma "vendor:miniaudio"
import "core:testing"

MicContext :: struct {
    ma_ctx: ma.context_type,
    device: ma.device,
    config: ma.device_config,
    playback_info: [^]ma.device_info,
    capture_info: [^]ma.device_info,
    playback_count: u32,
    capture_count: u32,
    current_idx: u32,
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
    ctx.current_idx = idx
    return true
}

SetPeakDropSpeed :: proc(ctx: ^MicContext, value:f32) {
    ctx.peak_drop_speed = value
}

// --- Tests ---

@(private="file")
feed :: proc(ctx: ^MicContext, sample_rate: u32, channels: u32, samples: []f32) {
    device: ma.device
    device.pUserData = ctx
    device.sampleRate = sample_rate
    device.capture.channels = channels
    DataCallback(&device, nil, raw_data(samples), u32(len(samples)) / channels)
}

@(test)
test_peak_rises_at_once_and_falls_slowly :: proc(t: ^testing.T) {
    ctx: MicContext
    SetPeakDropSpeed(&ctx, 1)                                                              // one unit per second, 0.01 per sample at 100 Hz
    feed(&ctx, 100, 1, {0.5})
    testing.expect_value(t, GetPeak(&ctx), f32(0.5))
    feed(&ctx, 100, 1, {-0.8})                                                             // the sign does not matter
    testing.expect_value(t, GetPeak(&ctx), f32(0.8))

    feed(&ctx, 100, 1, {0, 0, 0})
    testing.expect(t, abs(GetPeak(&ctx) - 0.77) < 1e-5, "three silent samples drop it by 3 * 0.01")

    feed(&ctx, 100, 1, {0.1})                                                              // a quieter sound does not pull the peak down by itself
    testing.expect(t, abs(GetPeak(&ctx) - 0.76) < 1e-5)
}

@(test)
test_peak_settles_on_zero :: proc(t: ^testing.T) {
    ctx: MicContext = {peak = 0.05, peak_drop_speed = 1}
    silence: [20]f32
    feed(&ctx, 100, 1, silence[:])
    testing.expect_value(t, GetPeak(&ctx), f32(0))                                         // clamped, never negative

    loud: [4]f32 = {0.2, 0.9, 0.2, 0.2}
    feed(&ctx, 100, 2, loud[:])                                                            // stereo frames are all scanned
    testing.expect(t, GetPeak(&ctx) > 0.85)
}

@(test)
test_device_queries_without_devices :: proc(t: ^testing.T) {
    ctx: MicContext
    testing.expect_value(t, GetDeviceCount(&ctx), u32(0))
    testing.expect_value(t, len(GetDeviceName(&ctx, 0)), 0)
    testing.expect(t, !SetDevice(&ctx, 0), "nothing to select")
    SetPeakDropSpeed(&ctx, 3)
    testing.expect_value(t, ctx.peak_drop_speed, f32(3))
}
