"use strict";
// Content script for YouTube. It only reads the page and moves text: what to do comes from the Odin background (youtube_shorts/shorts.odin).
//   - asks "url:<address>" for every page. The reply is "redirect:<address>" (open the short as a full video), "short:<id> <saved> <show>" or "ok"
//   - adds a Save button to the action column of the Shorts player (like, dislike, comments, share ...). The desktop player has no such button,
//     the mobile one has. "Save" keeps the short in the list of the extension options, it does not touch your YouTube playlists.
// YouTube is one page that changes its address without loading, so the address is looked at every 400 ms (cheap: one string compare).

(function () {
	const api = globalThis.browser ?? globalThis.chrome;
	const BUTTON_CLASS = "odin-save-short";
	const ACTIVE_REEL = "ytd-reel-video-renderer[is-active]";

	// null: not a short, or the Save button is off
	let current = null;     // { id, saved, show }
	let lastHref = "";

	const ask = (text) => api.runtime.sendMessage(text);

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
			const [id, saved, show] = reply.slice("short:".length).split(" ");
			current = { id, saved: saved === "1", show: show === "1" };
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

	function createButton() {
		const wrapper = document.createElement("div");
		wrapper.className = BUTTON_CLASS;
		wrapper.style.cssText = "display:flex;flex-direction:column;align-items:center;margin:8px 0;color:#fff;font:500 12px Roboto,Arial,sans-serif;";
		const button = document.createElement("button");
		button.type = "button";
		button.style.cssText = "width:48px;height:48px;border:0;border-radius:50%;cursor:pointer;background:rgba(255,255,255,0.1);color:#fff;display:flex;align-items:center;justify-content:center;";
		button.innerHTML = "<svg viewBox='0 0 24 24' width='24' height='24' fill='currentColor' aria-hidden='true'><path></path></svg>";
		const label = document.createElement("span");
		label.style.marginTop = "4px";
		wrapper.append(button, label);
		button.addEventListener("click", async (event) => {
			event.stopPropagation();
			event.preventDefault();
			if (!current) {
				return;
			}
			const reply = await ask("toggle:" + current.id + "\t" + shortTitle());
			if (reply === "saved:1" || reply === "saved:0") {
				current.saved = reply === "saved:1";
			} else if (reply === "full") {
				label.textContent = "List full";
			}
			updateButtons();
		});
		return wrapper;
	}

	// The buttons follow `current`: one in the action column of the active short while the option is on, none otherwise
	function updateButtons() {
		const wanted = current && current.show && location.host !== "m.youtube.com";
		for (const wrapper of document.querySelectorAll("." + BUTTON_CLASS)) {
			if (!wanted || wrapper.closest(ACTIVE_REEL) === null) {
				wrapper.remove();
			}
		}
		if (!wanted) {
			return;
		}
		const column = actionColumn();
		if (!column) {
			return;     // the player is not drawn yet, the next tick tries again
		}
		let wrapper = column.querySelector("." + BUTTON_CLASS);
		if (!wrapper) {
			wrapper = createButton();
			// before the "more" button (the three dots) when there is one: it stays the last of the column
			const more = column.querySelector("#menu-button, #menu");
			column.insertBefore(wrapper, more && more.parentElement === column ? more : null);
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
