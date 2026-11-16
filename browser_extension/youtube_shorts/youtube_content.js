"use strict";
// Content script for YouTube. It only reads the page and moves text: what to do comes from the Odin background (youtube_shorts/shorts.odin).
//   - asks "url:<address>" for every page. The reply is "redirect:<address>" (open the short as a full video),
//     "short:<id> <saved> <show Save> <show Download>" or "ok"
//   - adds a Save and a Download button to the action column of the Shorts player (like, dislike, comments, share ...). The desktop player has no
//     Save button, the mobile one has. "Save" keeps the short in the list of the extension options, it does not touch your YouTube playlists.
//   - Download runs yt-dlp or youtube-dl through the native helper. When the button is ready it asks "ytdl?"; if the program is not on PATH the
//     click opens a panel: install it (the helper does) or open the repository. The decisions and all the addresses come from Odin.
// YouTube is one page that changes its address without loading, so the address is looked at every 400 ms (cheap: one string compare).

(function () {
	const api = globalThis.browser ?? globalThis.chrome;
	const SAVE_CLASS = "odin-save-short";
	const DOWNLOAD_CLASS = "odin-download-short";
	const PANEL_ID = "odin-download-panel";
	const ACTIVE_REEL = "ytd-reel-video-renderer[is-active]";

	// null: not a short
	let current = null;     // { id, saved, showSave, showDownload }
	let lastHref = "";
	let helper = "unknown"; // "unknown" | "ok" | "missing" (no yt-dlp / youtube-dl on PATH) | "nohelper" (the native helper is not installed)
	let links = null;       // { repository, alternative, install, helper } from the background
	let busy = false;       // a download or an install runs

	const ask = (text) => api.runtime.sendMessage(text);
	const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

	async function onPage() {
		const href = location.href;
		let reply;
		try {
			reply = await ask("url:" + href);
		} catch (error) {
			// the background did not answer (extension reloaded): try again on the next tick
			lastHref = "";
			return;
		}
		if (href !== location.href) {
			return;     // moved on while waiting
		}
		if (typeof reply === "string" && reply.startsWith("redirect:")) {
			location.replace(reply.slice("redirect:".length));
			return;
		}
		if (typeof reply === "string" && reply.startsWith("short:")) {
			const [id, saved, showSave, showDownload] = reply.slice("short:".length).split(" ");
			current = { id, saved: saved === "1", showSave: showSave === "1", showDownload: showDownload === "1" };
		} else {
			current = null;
		}
		updateButtons();
	}

	function shortTitle() {
		const heading = document.querySelector(ACTIVE_REEL + " h2");
		const text = heading?.innerText?.trim();
		return text ? text : document.title.replace(/ - YouTube$/, "");
	}

	// The column of the active short that holds the native buttons. The id #actions is where the desktop player has them, the
	// fallback is the parent of the like button in case YouTube renames it.
	function actionColumn() {
		const reel = document.querySelector(ACTIVE_REEL);
		if (!reel) {
			return null;
		}
		return reel.querySelector("#actions")
			?? reel.querySelector("#like-button, like-button-view-model, [aria-label^='like this video' i]")?.parentElement
			?? null;
	}

	const BOOKMARK_OUTLINE = "M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2zm0 15-5-2.2L7 18V5h10v13z";
	const BOOKMARK_FILLED = "M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2z";
	const DOWNLOAD_ICON = "M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z";

	// A round button with a label under it, like the native ones of the column
	function createButton(className, path, onClick) {
		const wrapper = document.createElement("div");
		wrapper.className = className;
		wrapper.style.cssText = "display:flex;flex-direction:column;align-items:center;margin:8px 0;color:#fff;font:500 12px Roboto,Arial,sans-serif;";
		const button = document.createElement("button");
		button.type = "button";
		button.style.cssText = "width:48px;height:48px;border:0;border-radius:50%;cursor:pointer;background:rgba(255,255,255,0.1);color:#fff;display:flex;align-items:center;justify-content:center;";
		button.innerHTML = "<svg viewBox='0 0 24 24' width='24' height='24' fill='currentColor' aria-hidden='true'><path></path></svg>";
		button.querySelector("path").setAttribute("d", path);
		const label = document.createElement("span");
		label.style.marginTop = "4px";
		wrapper.append(button, label);
		button.addEventListener("click", (event) => {
			event.stopPropagation();
			event.preventDefault();
			onClick(wrapper);
		});
		return wrapper;
	}

	async function toggleSave(wrapper) {
		if (!current) {
			return;
		}
		const label = wrapper.querySelector("span");
		const reply = await ask("toggle:" + current.id + "\t" + shortTitle());
		if (reply === "saved:1" || reply === "saved:0") {
			current.saved = reply === "saved:1";
		} else if (reply === "full") {
			label.textContent = "List full";
		}
		updateButtons();
	}

	// --- Download ---

	async function loadLinks() {
		if (!links) {
			const reply = await ask("links");
			links = Object.fromEntries(reply.split(" ").map((pair) => [pair.slice(0, pair.indexOf("=")), pair.slice(pair.indexOf("=") + 1)]));
		}
		return links;
	}

	// "ytdl:ok", "ytdl:missing" or "ytdl:nohelper": whether the program that downloads is there. Asked when the button is ready.
	async function checkHelper() {
		const reply = await ask("ytdl?");
		helper = reply.startsWith("ytdl:") ? reply.slice("ytdl:".length) : "unknown";
		updateButtons();
		return helper;
	}

	// Waits for a job of the helper to end: "status:done <file>" / "status:failed <code>"
	async function waitForJob(job) {
		for (let i = 0; i < 2400; i++) {
			await sleep(1500);
			const reply = await ask("status:" + job);
			if (!reply.startsWith("status:running")) {
				return reply.slice("status:".length);
			}
		}
		return "failed timeout";
	}

	function setLabel(text, title) {
		for (const label of document.querySelectorAll("." + DOWNLOAD_CLASS + " span")) {
			label.textContent = text;
			label.parentElement.querySelector("button").title = title ?? text;
		}
	}

	async function startDownload() {
		if (!current || busy) {
			return;
		}
		const id = current.id;
		if (helper === "unknown") {
			await checkHelper();
		}
		if (helper !== "ok") {
			showPanel();
			return;
		}
		busy = true;
		setLabel("Starting...");
		const reply = await ask("download:" + id);
		if (reply.startsWith("ytdl:")) {
			// the program went away since the check, or the helper
			busy = false;
			helper = reply.slice("ytdl:".length);
			setLabel("Download");
			showPanel();
			return;
		}
		if (!reply.startsWith("job:")) {
			busy = false;
			setLabel("Failed", "The download did not start: " + reply);
			await sleep(4000);
			setLabel("Download");
			return;
		}
		setLabel("Downloading...");
		const result = await waitForJob(id);
		busy = false;
		if (result.startsWith("done")) {
			setLabel("Done", result.slice("done".length).trim() || "Saved to the Downloads folder");
		} else {
			setLabel("Failed", "youtube-dl / yt-dlp stopped: " + result);
		}
		await sleep(5000);
		setLabel("Download");
	}

	// The panel for a download that cannot start: what is missing, and what can be done about it
	function removePanel() {
		document.getElementById(PANEL_ID)?.remove();
	}

	function panelButton(text, onClick) {
		const button = document.createElement("button");
		button.type = "button";
		button.textContent = text;
		button.style.cssText = "margin:6px 6px 0 0;padding:6px 12px;border:0;border-radius:16px;cursor:pointer;background:#3ea6ff;color:#0f0f0f;font:500 13px Roboto,Arial,sans-serif;";
		button.addEventListener("click", (event) => {
			event.stopPropagation();
			onClick(button);
		});
		return button;
	}

	async function showPanel() {
		removePanel();
		const address = await loadLinks();
		const panel = document.createElement("div");
		panel.id = PANEL_ID;
		panel.style.cssText = "position:fixed;z-index:2147483647;right:90px;bottom:120px;max-width:320px;padding:14px;border-radius:12px;background:#212121;color:#fff;font:400 14px Roboto,Arial,sans-serif;box-shadow:0 4px 24px rgba(0,0,0,0.5);";
		const text = document.createElement("div");
		panel.append(text);
		const open = (url) => window.open(url, "_blank", "noopener");

		if (helper === "nohelper") {
			text.textContent = "The download helper is not installed for this browser, so the extension cannot start a download.";
			panel.append(panelButton("How to install it", () => open(address.helper)));
		} else {
			text.textContent = "Downloading needs yt-dlp or youtube-dl, and neither was found on PATH.";
			panel.append(panelButton("Install yt-dlp", async (button) => {
				button.disabled = true;
				text.textContent = "Installing yt-dlp...";
				const reply = await ask("install");
				const result = reply.startsWith("job:") ? await waitForJob("install") : "failed " + reply;
				if (result.startsWith("done") && (await checkHelper()) === "ok") {
					removePanel();
					setLabel("Download");
					return;
				}
				button.disabled = false;
				text.textContent = "The install did not work (" + result + "). Open the repository for the manual steps.";
			}));
			panel.append(panelButton("yt-dlp repository", () => open(address.repository)));
			panel.append(panelButton("youtube-dl repository", () => open(address.alternative)));
		}
		panel.append(panelButton("Close", removePanel));
		document.body.append(panel);
	}

	// --- Buttons ---

	// The buttons follow `current`: they live in the action column of the active short while their option is on, none otherwise
	function updateButtons() {
		const isMobile = location.host === "m.youtube.com";    // its player has a Save button already, and downloads are for the desktop
		const wanted = {
			[SAVE_CLASS]: current && current.showSave && !isMobile,
			[DOWNLOAD_CLASS]: current && current.showDownload && !isMobile,
		};
		for (const className of [SAVE_CLASS, DOWNLOAD_CLASS]) {
			for (const wrapper of document.querySelectorAll("." + className)) {
				if (!wanted[className] || wrapper.closest(ACTIVE_REEL) === null) {
					wrapper.remove();
				}
			}
		}
		if (!current || isMobile) {
			removePanel();
		}
		const column = actionColumn();
		if (!column) {
			return;     // the player is not drawn yet, the next tick tries again
		}
		// before the "more" button (the three dots) when there is one: it stays the last of the column
		const more = column.querySelector("#menu-button, #menu");
		const before = more && more.parentElement === column ? more : null;

		if (wanted[SAVE_CLASS]) {
			let wrapper = column.querySelector("." + SAVE_CLASS);
			if (!wrapper) {
				wrapper = createButton(SAVE_CLASS, BOOKMARK_OUTLINE, toggleSave);
				column.insertBefore(wrapper, before);
			}
			const button = wrapper.querySelector("button");
			button.setAttribute("aria-label", current.saved ? "Remove from saved shorts" : "Save short");
			button.title = button.getAttribute("aria-label");
			button.querySelector("path").setAttribute("d", current.saved ? BOOKMARK_FILLED : BOOKMARK_OUTLINE);
			const label = wrapper.querySelector("span");
			if (label.textContent !== "List full") {
				label.textContent = current.saved ? "Saved" : "Save";
			}
		}
		if (wanted[DOWNLOAD_CLASS]) {
			let wrapper = column.querySelector("." + DOWNLOAD_CLASS);
			if (!wrapper) {
				wrapper = createButton(DOWNLOAD_CLASS, DOWNLOAD_ICON, startDownload);
				wrapper.querySelector("span").textContent = busy ? "Downloading..." : "Download";
				wrapper.querySelector("button").setAttribute("aria-label", "Download video");
				column.insertBefore(wrapper, before);
				// the button is ready: find out whether it can work
				if (helper === "unknown") {
					checkHelper();
				}
			}
		}
	}

	function tick() {
		if (location.href !== lastHref) {
			lastHref = location.href;
			current = null;
			updateButtons();
			onPage();
		} else {
			// the player draws a short a moment after the address changed, and again when the user scrolls to the next one
			updateButtons();
		}
	}

	tick();
	setInterval(tick, 400);
	// a navigation inside of YouTube fires this, no need to wait for the timer then
	document.addEventListener("yt-navigate-finish", tick);
})();
