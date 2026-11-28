#+build js
// Runs the text kernels of the simd package in the page (a web_build package: init, step, shutdown) and reports to the page (simd_web_check.js)
package game

import simd "../.."

foreign import web "simd_web_check"

@(default_calling_convention = "contextless")
foreign web {
	report :: proc(failed: int, ran: int, kernels_ran: bool) ---
}

init :: proc() {
	failed, ran, kernels_ran := simd.TextWebCheck()
	report(failed, ran, kernels_ran)
}

step :: proc() -> bool {
	return false
}

shutdown :: proc() {}
