// The page side of simd/web_check: shows the result where a person or `--dump-dom` of a headless browser reads it
const simdWebCheckImports = {
	simd_web_check: {
		report: function (failed, ran, kernelsRan) {
			const text = "SIMD128 " + (failed === 0 && kernelsRan ? "PASS" : "FAIL") + ": " + failed + " of " + ran + " checks failed, simd128 kernels " + (kernelsRan ? "ran" : "DID NOT RUN") + ", wasm simd " + simdWebCheckSupported();
			document.title = text;
			const out = document.createElement("pre");
			out.id = "result";
			out.textContent = text;
			document.body.appendChild(out);
			console.log(text);
		},
	},
};

// Does this browser validate a module that uses a v128 instruction (a module with one function: i32x4.splat, drop)
function simdWebCheckSupported() {
	const bytes = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 10, 9, 1, 7, 0, 65, 0, 253, 17, 26, 11]);
	return WebAssembly.validate(bytes);
}
