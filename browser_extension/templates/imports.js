"use strict";
// The procs that runtime/runtime.odin declares (module "extension"), shared by the background and the extension pages.
// Strings come as pointer and length into the wasm memory.
globalThis.extensionImports = function (memory) {
	const api = globalThis.browser ?? globalThis.chrome;
	return {
		extension: {
			log: (pointer, length) => console.log("[odin]", memory.loadString(pointer, length)),
			set_badge: (pointer, length) => api.action.setBadgeText({ text: memory.loadString(pointer, length) }),
			open_url: (pointer, length) => api.tabs.create({ url: memory.loadString(pointer, length) }),
			save_state: (pointer, length) => api.storage.local.set({ state: memory.loadString(pointer, length) }),
			// the reply is handed to extensionOnReply, which the loader of the page sets
			send_message: (pointer, length) => {
				api.runtime.sendMessage(memory.loadString(pointer, length)).then(
					(reply) => globalThis.extensionOnReply?.(reply ?? ""),
					(error) => console.warn("[odin] no answer:", error),
				);
			},
		},
	};
};
