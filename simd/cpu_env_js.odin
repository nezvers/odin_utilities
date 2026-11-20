#+build js
package simd_utils

// The web has no environment
@(private)
cpuApplyEnvironment :: proc "contextless" (cpu: ^Cpu) {
}
