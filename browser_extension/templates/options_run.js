"use strict";
// Runs the options page: a web_build package (init, step, shutdown) in a canvas, the same flow as web_build's index.html but as a file,
// because extension pages may not run inline scripts. {{IMPORTS}} and {{START}} are filled in by the build.
(async function () {
	const api = globalThis.browser ?? globalThis.chrome;
	const encoder = new TextEncoder();
	// no inline handlers (the page may not run them): the canvas takes the focus for the keyboard, the context menu stays out of the way
	const canvas = document.getElementById("webgl-canvas");
	canvas.addEventListener("contextmenu", (event) => event.preventDefault());
	canvas.addEventListener("mousedown", () => canvas.focus());
	const wasmMemoryInterface = new odin.WasmMemoryInterface();
	wasmMemoryInterface.setIntSize(4);

	const imports = {
		...odin.setupDefaultImports(wasmMemoryInterface, null, wasmMemoryInterface.memory),
		...extensionImports(wasmMemoryInterface),
		...({{IMPORTS}}),
	};
	const response = await fetch("main.wasm");
	const wasm = await WebAssembly.instantiate(await response.arrayBuffer(), imports);
	const exports = wasm.instance.exports;
	wasmMemoryInterface.setExports(exports);

	if (exports.memory) {
		wasmMemoryInterface.setMemory(exports.memory);
		{{START}}
	}

	// replies of the background go to reply_ready of runtime/runtime.odin
	globalThis.extensionOnReply = (text) => {
		const bytes = encoder.encode(text).slice(0, exports.reply_capacity());
		new Uint8Array(exports.memory.buffer, exports.reply_pointer(), bytes.length).set(bytes);
		exports.reply_ready(bytes.length);
	};

	if (exports._start) {
		exports._start();
	}

	if (exports.step) {
		const odin_ctx = exports.default_context_ptr();
		let prevTimeStamp = undefined;
		function step(currTimeStamp) {
			if (prevTimeStamp == undefined) {
				prevTimeStamp = currTimeStamp;
			}
			const dt = (currTimeStamp - prevTimeStamp) * 0.001;
			prevTimeStamp = currTimeStamp;

			if (!exports.step(dt, odin_ctx)) {
				if (exports.shutdown) {
					exports.shutdown(dt, odin_ctx);
				}
				if (exports._end) {
					exports._end();
				}
				return;
			}
			window.requestAnimationFrame(step);
		}
		window.requestAnimationFrame(step);
	}
})();
