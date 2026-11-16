"use strict";
// Background of the extension. Chrome, Opera and Edge run it as a service worker (the manifest lists only this file, so the other
// scripts are imported), Firefox runs it as an event page after the scripts its manifest lists.
if (typeof importScripts === "function") {
	// odin.js attaches itself to `window`, a worker has none
	self.window = self;
	importScripts("odin.js", "imports.js", "extension.js");
}

const api = globalThis.browser ?? globalThis.chrome;
// The native messaging host of the extension (ExtensionConfig.native_host), "" when it has none
const NATIVE_HOST = "{{NATIVE_HOST}}";

// Odin answers with text. An answer "native:<text>" is not for the sender: the text goes to the native host (a program on this computer, the only
// way to run one), its answer or its error goes back to Odin as "native-reply:<text>" / "native-error:<why>", and Odin's reply to that is the answer.
// The JavaScript only carries, Odin decides what is sent and what the result means.
async function answer(text) {
	let reply = ExtensionWasm.message(text);
	for (let round = 0; round < 4 && reply.startsWith("native:"); round++) {
		let back;
		try {
			const response = await api.runtime.sendNativeMessage(NATIVE_HOST, { m: reply.slice("native:".length) });
			back = "native-reply:" + (response && typeof response.m === "string" ? response.m : "");
		} catch (error) {
			back = "native-error:" + (error && error.message ? error.message : String(error));
		}
		reply = ExtensionWasm.message(back);
	}
	return reply;
}

// A service worker is stopped when idle and started again for the next event, so Odin state does not survive: SaveState and on_load keep it.
// Listeners are added in the first turn of the script, otherwise the event that woke the worker is lost.
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
	ExtensionWasm.loaded.then(() => answer(typeof message === "string" ? message : JSON.stringify(message))).then(sendResponse);
	// the reply comes after wasm is loaded
	return true;
});
