"use strict";
// Loads main.wasm (the Odin side of the extension) and connects it to the browser. Shared by the background of every browser.
// Needs odin.js (the Odin JavaScript runtime) loaded before it.
//
// The Odin package exports a fixed input buffer and a fixed output buffer, a message is copied into the first, `message(length)`
// is called and the reply is read from the second. Nothing is allocated on either side per message.
(function () {
	const api = globalThis.browser ?? globalThis.chrome;
	const encoder = new TextEncoder();
	const decoder = new TextDecoder();
	let exports = null;

	// The procs of runtime/runtime.odin, module name "extension"
	function extensionImports(memory) {
		return {
			extension: {
				log: (pointer, length) => console.log("[odin]", memory.loadString(pointer, length)),
				set_badge: (pointer, length) => api.action.setBadgeText({ text: memory.loadString(pointer, length) }),
			},
		};
	}

	async function load() {
		const memory = new odin.WasmMemoryInterface();
		memory.setIntSize(4);
		const imports = { ...odin.setupDefaultImports(memory, null, memory.memory), ...extensionImports(memory) };

		const response = await fetch(api.runtime.getURL("main.wasm"));
		const wasm = await WebAssembly.instantiate(await response.arrayBuffer(), imports);
		exports = wasm.instance.exports;
		memory.setExports(exports);
		memory.setMemory(exports.memory);
		// runs `main` of the generated entry, which is the `init` of the Odin package
		exports._start();
	}

	// Send a text to the Odin side, get its reply. Only after `loaded` resolved.
	function message(text) {
		const bytes = encoder.encode(text);
		const capacity = exports.input_capacity();
		if (bytes.length > capacity) {
			throw new Error("message of " + bytes.length + " bytes does not fit the input buffer of " + capacity);
		}
		// the memory can grow, so the buffer is read again every call
		new Uint8Array(exports.memory.buffer, exports.input_pointer(), bytes.length).set(bytes);
		const length = exports.message(bytes.length);
		return decoder.decode(new Uint8Array(exports.memory.buffer, exports.output_pointer(), length));
	}

	globalThis.ExtensionWasm = { loaded: load(), message };
})();
