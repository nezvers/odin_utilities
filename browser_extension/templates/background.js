"use strict";
// Background of the extension. Chrome, Opera and Edge run it as a service worker (the manifest lists only this file, so the other
// scripts are imported), Firefox runs it as an event page after odin.js and extension.js (listed in its manifest).
if (typeof importScripts === "function") {
	// odin.js attaches itself to `window`, a worker has none
	self.window = self;
	importScripts("odin.js", "extension.js");
}

const api = globalThis.browser ?? globalThis.chrome;

// A service worker is stopped when idle and started again for the next event, so Odin state does not survive: keep what has to stay
// in api.storage. Listeners are added in the first turn of the script, otherwise the event that woke the worker is lost.
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
	ExtensionWasm.loaded.then(() => {
		sendResponse(ExtensionWasm.message(typeof message === "string" ? message : JSON.stringify(message)));
	});
	// the reply comes after wasm is loaded
	return true;
});
