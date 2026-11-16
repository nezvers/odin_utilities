# youtube_shorts: Shorts Helper

An example extension for `browser_extension` with most of the logic in Odin. Two things for YouTube Shorts:

1. **Open Shorts as a full video.** `youtube.com/shorts/<id>` becomes `youtube.com/watch?v=<id>`: the normal player with the timeline, the description and the recommendations. An option, off by default.
2. **A Save button on every video**, a short or a normal one. In the desktop Shorts player it is in the column of the native buttons (like, comments, share, remix; the mobile player has a Save button, the desktop one has not), under a normal video it is in the row of like and share. On by default. Saved videos are listed on the options page (Open, Remove). Where YouTube draws no place for the buttons (the page changed, or it is not drawn yet) they appear in a small bar in the bottom right corner after about two seconds, so they are on any video.

3. **A Download button** next to Save. It runs `yt-dlp` or `youtube-dl` (whichever is on PATH, yt-dlp first) through a small helper program, see [Download helper](#download-helper). When the button appears the extension checks for the program; if there is none, a click opens a panel with **Install yt-dlp**, **yt-dlp repository** and **youtube-dl repository**. On by default; downloading is your decision and your responsibility, check the terms of the site and the rights to the video.

"Save" keeps the short in a list inside of the extension (up to 64, in the browser storage of the extension). It does not touch your YouTube playlists.

## Where the logic is
```
youtube_shorts/
├── shorts.odin              ALL decisions, no browser in it: parse a Shorts address, build the watch address, the settings, the saved list
│                            (fixed 64 entries, newest first), the text form for the storage, ShortsHandle = the messages of the page
├── shorts_test.odin         odin test youtube_shorts
├── background/              the background (wasm): keeps the Store, answers messages, SaveState / on_load   (about 30 lines)
├── options/                 the options page as a demo_kit demo: toggles and the list, the loopback "background" for the desktop and the tests
├── host_raylib/             the options page in a raylib window (desktop preview, no browser)
├── host_karl2d/             the options page in the extension: Karl2D in a canvas (js_wasm32), the bridge is runtime.SendMessage
├── native/                  the logic of the download helper: find yt-dlp / youtube-dl, start a download or an install job, report its status (tests)
├── native_host/             the helper program itself (native messaging: stdin/stdout packets), a few lines around `native/`
├── youtube_content.js       the content script: reads the page, moves text, adds the buttons and the panel. Asks the background what to do
└── tool/main.odin           build (and install) the extension
```
The JavaScript only does what Odin cannot: it sees the address, the DOM and the clicks, sends `url:<address>` and gets one of `redirect:<watch address>`, `short:<id> <saved> <show the button>` or `ok`. It never decides. Messages are in the comment of `ShortsHandle`.

## Download helper
An extension cannot start programs, only a **native messaging host** can: `native_host` is that program (Odin, `bin/native/shorts_helper_host.exe`). The build tool compiles it, and `--install` registers it for the browser: a manifest file in `bin/extension/native/` plus, on Windows, a value under `HKCU\Software\<Google\Chrome | Microsoft\Edge | Mozilla>\NativeMessagingHosts\com.odin_utilities.shorts_helper` (per user, no administrator; Opera reads the Chrome key). Only this extension may use it (`allowed_origins` is the id of the extension loaded from `bin/extension/chromium`, `allowed_extensions` the add-on id in Firefox). To remove it, delete that registry value. Without `--install` (manual load of the folder) the browser does not know the helper and the Download button says so: register it by running the tool with `--install` once, or by hand with the manifest of `bin/extension/native/`.

What happens on a click: content script `download:<id>` -> background (Odin) -> `native:download:<id>` -> the browser starts the helper, which checks for yt-dlp / youtube-dl and starts a **job** (a detached copy of the helper) that runs the program: `--no-playlist -o "<Downloads>/%(title)s [%(id)s].%(ext)s" https://www.youtube.com/watch?v=<id>`. The page polls `status:<id>` (the job writes `<temp>/shorts_helper/<id>.status`), the button shows Downloading..., Done (the tooltip has the file) or Failed. The helper looks for `yt-dlp`, then `youtube-dl` on PATH of the browser, then in `<temp>/shorts_helper/bin` where **Install yt-dlp** puts the release exe (Windows: `curl` from the GitHub release; Linux and macOS: `python3 -m pip install --user -U yt-dlp`). A browser started before you changed PATH does not see the change.

## raylib and Karl2D for the options
The options page is written once against `demo_kit` (`options/options.odin`) and runs on both:
- **Karl2D**, in the extension: the options page (`options/options.html`) is a canvas, `host_karl2d` is a web_build package (`init`, `step`, `shutdown`). Messages go to the background, the replies come back to `OptionsOnReply`.
- **raylib**, on the desktop: `odin run youtube_shorts/host_raylib` opens the same page with a loopback background that has three saved shorts, no browser needed. Fast to work on the layout.
- The script of the page (clicks on the toggles and on Remove / Open, checks of what the page shows and what the background kept) is a test: `odin test youtube_shorts/options` headless, or in the raylib window with `-define:DEMO_TEST=true`.

## Build and install
From `odin_utilities/browser_extension`:
```
odin run youtube_shorts/tool -- all                  # chrome | opera | edge | firefox | all
odin run youtube_shorts/tool -- chrome --install     # build and start the browser with the extension
```
Output in `youtube_shorts/bin/extension/` (`chromium/`, `firefox/`, `Shorts_Helper-chromium.zip`, `Shorts_Helper-firefox.zip`). Manual install steps for each browser are in `../README.md`. VS Code: the launch configurations "Shorts: ..." and tasks "Shorts: ...".

The toolbar button opens a small popup (`popup.html`, `popup.js`): the three settings as checkboxes, a button to the full options page (saved shorts), and, in Firefox, an "Allow on YouTube" button while the host permission is off. The build passes `web-ext lint` (the add-ons validator) with no warnings: two lines of Odin's `odin.js` (`innerHTML` of its page console, `eval` of the `evaluate` import) are replaced in the copy the extension gets.

For the browser you use every day (main profile) run the same tool with `--release` instead of `--install` (VS Code: "Shorts: Release ... (main profile)"). Chrome, Opera and Edge: it copies the extension and the helper to `%LOCALAPPDATA%\Shorts_Helper`, registers the helper, opens the browser on its extensions page, and you press **Load unpacked** once (Developer mode on, the folder is in the clipboard). Firefox: it signs the build with Mozilla as an unlisted add-on and opens the signed file, which needs free Mozilla keys (see `../README.md`): put them in `tool/signing.odin` (a template, git ignored after its first commit, so your secret is never committed) or in `WEB_EXT_API_KEY` / `WEB_EXT_API_SECRET` and a new `version` in `tool/main.odin` for every release. A later update is the same command, then the reload button of the extension (Chrome family).

Using it: **Details / Extension options** of the extension opens the options page in a tab (Chrome: right click the icon, Options; Firefox: add-ons page, the extension, Preferences). Turn on "Open Shorts as a full video" and a short opens in the normal player; leave it off, open a short on desktop YouTube and the Save button is below the share button.

## What was checked
- `odin test youtube_shorts`, `odin test youtube_shorts/options`, the raylib window with `-define:DEMO_TEST=true`.
- In Edge (Chromium) with the extension loaded, end to end: the options page (Karl2D) toggles the redirect option and the background answers; a short address is replaced by the watch address; the Save button is added before the "more" button, a click saves, a second click removes, the state is in `chrome.storage.local` and the options page lists it.
- **On the real youtube.com** (a throwaway profile, cookies accepted), logged out: in Edge and in Firefox 160 (WebDriver BiDi) a short (`/shorts/<id>`) gets Save and Download in `reel-action-bar-view-model`, the column of the desktop player, and a normal video (`/watch?v=<id>`) gets them in `#top-level-buttons-computed`, the row under the video. Both look like the native buttons (round 48 px in the column, pills in the row). A first version used selectors from memory (`ytd-reel-video-renderer[is-active] #actions`) and showed nothing on the real page, the layout above was read from the live page. YouTube renames things now and then: if both places are missing the floating bar is the fallback (tested on a page with neither). The older `#actions` of the reel is still tried for older layouts.
- Mock pages (served instead of youtube.com) were used for the cases the real page cannot give: redirect, the missing-program panel, the floating bar.
- Chrome itself was not installed: Chrome, Opera and Edge share the Chromium build, Opera GX and Edge ran it.
- Download, in Edge with the real helper (`odin test youtube_shorts/native` for the rest): the button is added after Save, the label goes Downloading... then Done and the tooltip has the file the program wrote; with no yt-dlp / youtube-dl on PATH a click opens the panel with Install and both repositories; an extension the helper does not allow gets the "helper is not installed" panel. Opera GX finds the helper through the Chrome key. The download program in those tests was a fake `yt-dlp.exe` (no video was downloaded), the **Install yt-dlp** button was not pressed (it would download and run a program on this machine), and Firefox was not tried with the helper (the registration for it is written the same way, untested).
- Firefox accepts the add-on (`installTemporaryAddon`), its pages were not driven.

## Firefox
Firefox treats the site permissions of a Manifest V3 extension as optional. A temporary add-on (the tool's `firefox --install`) works at once, but when the extension is installed another way and the permission is off, the content script does not run and nothing shows. The toolbar button then has a "!" badge: click it, allow the sites, reload the YouTube tab. (The same switch is in `about:addons`, the extension, Permissions.) A temporary add-on is gone when Firefox closes.

## Limits
- A short that needs an account (age limit, private) or that youtube-dl cannot read fails with Failed, the tooltip has the exit code. youtube-dl is much slower to follow YouTube than yt-dlp, which is why yt-dlp goes first.
- Saved titles are cut at 80 bytes. 64 shorts at most: the 65th Save shows "List full" instead of growing the list.
- `m.youtube.com` gets the redirect but no Save button (its player has one).
- The state of the background (the list) lives in the browser storage of the extension, it is not synced between browsers or devices.
