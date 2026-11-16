"use strict";
// The popup only talks to the background, where the Odin code runs. Replace the text to send whatever your on_message understands.
const api = globalThis.browser ?? globalThis.chrome;

document.getElementById("ping").addEventListener("click", () => {
	api.runtime.sendMessage("ping").then(
		(reply) => { document.getElementById("reply").textContent = reply; },
		(error) => { document.getElementById("reply").textContent = String(error); },
	);
});
