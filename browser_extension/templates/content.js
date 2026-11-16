"use strict";
// Content script: runs in the pages that match the manifest. It tells the background (Odin) which page it is on.
(globalThis.browser ?? globalThis.chrome).runtime.sendMessage("page:" + document.title);
