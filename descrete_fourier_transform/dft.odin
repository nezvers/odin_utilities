package discrete_fourier_transform

// translated from https://github.com/SebLague/Audio-Experiments

import math "core:math"
import thread "core:thread"
import parallel "parallel"

PI :: math.PI
TAU :: math.TAU

FrequencyData :: struct {
    frequency:f32,
    amplitude:f32,
    phase:f32,
}

vec2 :: [2]f32

// Returns magnitude of vector
vec2_mag :: proc(a: vec2) -> f32{
    return math.sqrt(a.x * a.x + a.y * a.y)
}

DFT :: proc(samples:[]f32, sample_rate:u32)->[]FrequencyData {
    sample_count:u32 = cast(u32)len(samples)
    // If a signal is sampled for 1 second, only integer frequencies appear periodic.
    // With a duration of 2 seconds, every increment of 0.5 Hz appears periodic, and so on.
    // Additionally, from Nyquist we know we can detect a maximum frequency of sampleRate / 2.
    // So, the number of frequencies is sampleRate / 2 * duration. (Equivalently: numSamples / 2)
    // Add one since we want to start at 0 Hz
    num_frequencies:u32 = sample_count / 2 + 1
    spectrum:[]FrequencyData = make([]FrequencyData, num_frequencies)

    // Calculate the size of the frequency steps such that the last value in the spectrum will be the
    // max frequency (Note: max frequency only exactly represented when sample count is even) 
    frequency_step:f32 = sample_rate / cast(f32)sample_count; // Equivalent to 1 / duration

    // TODO: parrallel with threads
    for freq_index in 0..< num_frequencies {
        sample_count_f:f32 = cast(f32)sample_count
        index_f:f32 = cast(f32)freq_index
        sample_sum:vec2 = {}
        for i in 0..< sample_count {
            t:f32 = cast(f32)i / sample_count_f
            angle:f32 = t * TAU * index_f
            test_point:vec2 = {math.cos(angle), math.sin(angle)}
            sample_sum += test_point * samples[i]
        }

        sample_centre:vec2 = sample_sum / sample_count_f
        is_0Hz:bool = freq_index == 0

        // The last frequency is equal to samplerate/2 only if sample count is even
        is_nyquist_freq:bool = freq_index == num_frequencies - 1 && sample_count % 2 == 0
        amplitude_scale:f32 = is_0Hz || is_nyquist_freq ? 1.0 : 2.0

        amplitude:f32 = vec2_mag(sample_centre) * amplitude_scale
        frequency:f32 = frequency_step * index_f
        phase:f32 = -math.atan2(sample_centre.y, sample_centre.x)
        
        spectrum[freq_index] = {frequency, amplitude, phase}
    }

    return spectrum
}
