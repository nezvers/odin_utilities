"use strict";
// Content script for YouTube (a normal video or a short). It only reads the page and moves text: what to do comes from the Odin background
// (youtube_shorts/shorts.odin).
//   - asks "url:<address>" for every page. The reply is "redirect:<address>" (open the short as a full video),
//     "video:<id> <short> <saved> <show Save> <show Download>" or "ok" (not a video)
//   - adds a Save and a Download button. Where they go, in this order:
//       a short:        the action column of the desktop player (like, comments, share, remix ...), round buttons
//       a normal video: the row of buttons under the video (like, share ...), pill buttons
//       otherwise (YouTube changed its page, or it is not drawn): a floating bar in the corner, so the buttons are always there
//   - Save keeps the video in the list of the extension options, it does not touch your YouTube playlists.
//   - Download runs yt-dlp or youtube-dl through the native helper. When the button is ready it asks "ytdl?"; if the program is not on PATH the
//     click opens a panel: install it (the helper does) or open the repository. The decisions and all the addresses come from Odin.
// YouTube is one page that changes its address without loading, so the address is looked at every 400 ms (cheap: one string compare).

(function () {
	const api = globalThis.browser ?? globalThis.chrome;
	const SAVE_CLASS = "odin-save-short";
	const DOWNLOAD_CLASS = "odin-download-short";
	const FLOATING_ID = "odin-floating-bar";
	const PANEL_ID = "odin-download-panel";
	const FALLBACK_TICKS = 5;   // 400 ms each: this long the page gets to draw its own buttons before the floating bar shows

	// null: not a video
	let current = null;     // { id, isShort, saved, showSave, showDownload }
	let lastHref = "";
	let waitingTicks = 0;   // ticks without a place for the buttons on this page
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
			// the background did not answer (extension reloaded, event page starting): try again on the next tick
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
		if (typeof reply === "string" && reply.startsWith("video:")) {
			const [id, isShort, saved, showSave, showDownload] = reply.slice("video:".length).split(" ");
			current = { id, isShort: isShort === "1", saved: saved === "1", showSave: showSave === "1", showDownload: showDownload === "1" };
		} else {
			current = null;
		}
		waitingTicks = 0;
		updateButtons();
	}

	// --- Where the buttons go ---

	function isVisible(element) {
		const rect = element.getBoundingClientRect();
		return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight && rect.right > 0 && rect.left < innerWidth;
	}

	// The action column of the short that is on the screen. The desktop player has `reel-action-bar-view-model`, the older one `#actions`
	// in the reel that is active. Several shorts can be in the page (the next and the last one), the one in view is the one.
	function shortsColumn() {
		const bars = [...document.querySelectorAll("reel-action-bar-view-model")];
		const visible = bars.find(isVisible);
		if (visible) {
			return visible;
		}
		return [...document.querySelectorAll("ytd-reel-video-renderer[is-active] #actions, ytd-reel-video-renderer #actions")].find(isVisible) ?? null;
	}

	// The row of buttons under a normal video (like, share, ...)
	function watchRow() {
		return document.querySelector("ytd-watch-metadata #top-level-buttons-computed")
			?? [...document.querySelectorAll("#top-level-buttons-computed")].find(isVisible)
			?? null;
	}

	function floatingBar() {
		let bar = document.getElementById(FLOATING_ID);
		if (!bar) {
			bar = document.createElement("div");
			bar.id = FLOATING_ID;
			bar.style.cssText = "position:fixed;z-index:2147483000;right:16px;bottom:16px;display:flex;gap:8px;";
			document.documentElement.append(bar);
		}
		return bar;
	}

	// { kind: "column" | "row" | "floating", container, before } or null (not now)
	function findSlot() {
		if (!current) {
			return null;
		}
		if (current.isShort) {
			const column = shortsColumn();
			if (column) {
				waitingTicks = 0;
				// the channel picture (or the menu) stays last
				const last = column.querySelector(":scope > pivot-button-view-model, :scope > #menu-button, :scope > #menu");
				return { kind: "column", container: column, before: last };
			}
		} else {
			const row = watchRow();
			if (row) {
				waitingTicks = 0;
				return { kind: "row", container: row, before: null };
			}
		}
		if (waitingTicks++ >= FALLBACK_TICKS) {
			return { kind: "floating", container: floatingBar(), before: null };
		}
		return null;
	}

	// --- Buttons ---

	const BOOKMARK_OUTLINE = "M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2zm0 15-5-2.2L7 18V5h10v13z";
	const BOOKMARK_FILLED = "M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2z";
	const DOWNLOAD_ICON = "M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z";

	// A button like the native ones of its place: round with the label under it (a short), a pill (a video, the floating bar)
	function createButton(className, path, onClick, kind) {
		const wrapper = document.createElement("div");
		wrapper.className = className;
		wrapper.dataset.slot = kind;
		const button = document.createElement("button");
		button.type = "button";
		button.innerHTML = "<svg viewBox='0 0 24 24' width='24' height='24' fill='currentColor' aria-hidden='true'><path></path></svg>";
		button.querySelector("path").setAttribute("d", path);
		const label = document.createElement("span");
		if (kind === "column") {
			wrapper.style.cssText = "display:flex;flex-direction:column;align-items:center;margin:8px 0;color:#fff;font:500 12px Roboto,Arial,sans-serif;";
			button.style.cssText = "width:48px;height:48px;border:0;border-radius:50%;cursor:pointer;background:rgba(255,255,255,0.1);color:#fff;display:flex;align-items:center;justify-content:center;";
			label.style.marginTop = "4px";
			wrapper.append(button, label);
		} else {
			const floating = kind === "floating";
			wrapper.style.cssText = "display:inline-flex;margin-left:" + (floating ? "0" : "8px") + ";";
			button.style.cssText = "height:36px;padding:0 16px 0 12px;border:0;border-radius:18px;cursor:pointer;display:flex;align-items:center;gap:6px;font:500 14px Roboto,Arial,sans-serif;"
				+ (floating
					? "background:rgba(33,33,33,0.95);color:#fff;box-shadow:0 2px 12px rgba(0,0,0,0.4);"
					: "background:var(--yt-spec-badge-chip-background,rgba(0,0,0,0.05));color:var(--yt-spec-text-primary,#0f0f0f);");
			button.querySelector("svg").setAttribute("width", "20");
			button.querySelector("svg").setAttribute("height", "20");
			button.append(label);
			wrapper.append(button);
		}
		button.addEventListener("click", (event) => {
			event.stopPropagation();
			event.preventDefault();
			onClick(wrapper);
		});
		return wrapper;
	}

	function videoTitle() {
		const column = shortsColumn();
		const reel = column?.closest("ytd-reel-video-renderer");
		const text = (current?.isShort ? reel?.querySelector("yt-shorts-video-title-view-model, h1, h2") : document.querySelector("ytd-watch-metadata h1"))?.innerText?.trim();
		return text ? text : document.title.replace(/ - YouTube$/, "");
	}

	async function toggleSave(wrapper) {
		if (!current) {
			return;
		}
		const label = wrapper.querySelector("span");
		const reply = await ask("toggle:" + current.id + "\t" + videoTitle());
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

	// Waits for a job of the helper to end: "done <file>" / "failed <code>"
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
			label.closest("div").querySelector("button").title = title ?? text;
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
			setLabel("Failed", "yt-dlp / youtube-dl stopped: " + result);
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
		panel.style.cssText = "position:fixed;z-index:2147483647;max-width:320px;padding:14px;border-radius:12px;background:#212121;color:#fff;font:400 14px Roboto,Arial,sans-serif;box-shadow:0 4px 24px rgba(0,0,0,0.5);";
		// next to the Download button: left of the column of a short, above the row or the bar of a video
		const anchor = document.querySelector("." + DOWNLOAD_CLASS);
		if (anchor) {
			const rect = anchor.getBoundingClientRect();
			if (anchor.dataset.slot === "column") {
				panel.style.right = Math.max(8, innerWidth - rect.left + 12) + "px";
				panel.style.top = Math.max(8, Math.min(rect.top - 40, innerHeight - 200)) + "px";
			} else {
				panel.style.right = Math.max(8, innerWidth - rect.right) + "px";
				panel.style.bottom = Math.max(8, innerHeight - rect.top + 8) + "px";
			}
		} else {
			panel.style.right = "16px";
			panel.style.bottom = "70px";
		}
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
		document.documentElement.append(panel);
	}

	// --- Put the buttons in place ---

	// The buttons follow `current` and the place the page offers: right kind of button in the right container, none when the option is off
	function updateButtons() {
		const slot = findSlot();
		const wanted = {
			[SAVE_CLASS]: !!(slot && current.showSave),
			[DOWNLOAD_CLASS]: !!(slot && current.showDownload),
		};
		for (const className of [SAVE_CLASS, DOWNLOAD_CLASS]) {
			for (const wrapper of document.querySelectorAll("." + className)) {
				// a button of another kind or in another container (the next short scrolled in, the page drew its row) goes
				if (!wanted[className] || wrapper.dataset.slot !== slot.kind || wrapper.parentElement !== slot.container) {
					wrapper.remove();
				}
			}
		}
		// the bar goes away when the buttons found a place of their own
		if (!slot || slot.kind !== "floating") {
			document.getElementById(FLOATING_ID)?.remove();
		}
		if (!slot) {
			removePanel();
			return;
		}

		if (wanted[SAVE_CLASS]) {
			let wrapper = slot.container.querySelector(":scope > ." + SAVE_CLASS);
			if (!wrapper) {
				wrapper = createButton(SAVE_CLASS, BOOKMARK_OUTLINE, toggleSave, slot.kind);
				slot.container.insertBefore(wrapper, slot.before);
			}
			const button = wrapper.querySelector("button");
			button.setAttribute("aria-label", current.saved ? "Remove from saved videos" : "Save video");
			button.title = button.getAttribute("aria-label");
			button.querySelector("path").setAttribute("d", current.saved ? BOOKMARK_FILLED : BOOKMARK_OUTLINE);
			const label = wrapper.querySelector("span");
			if (label.textContent !== "List full") {
				label.textContent = current.saved ? "Saved" : "Save";
			}
		}
		if (wanted[DOWNLOAD_CLASS]) {
			let wrapper = slot.container.querySelector(":scope > ." + DOWNLOAD_CLASS);
			if (!wrapper) {
				wrapper = createButton(DOWNLOAD_CLASS, DOWNLOAD_ICON, startDownload, slot.kind);
				wrapper.querySelector("span").textContent = busy ? "Downloading..." : "Download";
				wrapper.querySelector("button").setAttribute("aria-label", "Download video");
				slot.container.insertBefore(wrapper, slot.before);
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
			waitingTicks = 0;
			updateButtons();
			onPage();
		} else {
			// the player draws a moment after the address changed, and again when the user scrolls to the next short
			updateButtons();
		}
	}

	tick();
	setInterval(tick, 400);
	// a navigation inside of YouTube fires this, no need to wait for the timer then
	document.addEventListener("yt-navigate-finish", tick);
})();
