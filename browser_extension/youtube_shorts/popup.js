"use strict";
// The popup of the toolbar button: the three settings of the Shorts Helper. The settings text is made and read by Odin (shorts.odin,
// ShortsSettingsEncode/Decode: "redirect=1 save=1 download=1"); this file only shows it and sends the changed text back.
const api = globalThis.browser ?? globalThis.chrome;
const names = ["redirect", "save", "download"];
const note = document.getElementById("note");

function send(text) {
	return Promise.resolve(api.runtime.sendMessage(text));
}

function readSettings(text) {
	const result = {};
	for (const name of names) {
		const match = new RegExp(name + "=(\\d)").exec(text);
		result[name] = !match || match[1] === "1";
	}
	return result;
}

async function load() {
	try {
		const settings = readSettings(await send("get"));
		for (const name of names) {
			document.getElementById(name).checked = settings[name];
		}
	} catch (error) {
		note.textContent = String(error);
	}
}

for (const name of names) {
	document.getElementById(name).addEventListener("change", async () => {
		const text = names.map((n) => n + "=" + (document.getElementById(n).checked ? 1 : 0)).join(" ");
		try {
			await send("set:" + text);
			note.textContent = "Saved. Reload open YouTube tabs to see it.";
		} catch (error) {
			note.textContent = String(error);
		}
	});
}

document.getElementById("saved").addEventListener("click", () => {
	api.runtime.openOptionsPage();
	window.close();
});

// Firefox keeps the host permissions of a Manifest V3 extension off until the user allows them: then the content script does not run.
// A click in the popup is the gesture the permission prompt needs.
const origins = api.runtime.getManifest().host_permissions ?? [];
async function checkAllowed() {
	if (origins.length === 0 || !api.permissions?.contains) {
		return;
	}
	const granted = await api.permissions.contains({ origins });
	document.getElementById("allow").style.display = granted ? "none" : "block";
}
document.getElementById("allow-button").addEventListener("click", async () => {
	await api.permissions.request({ origins });
	await checkAllowed();
	note.textContent = "Allowed. Reload open YouTube tabs.";
});

load();
checkAllowed();
