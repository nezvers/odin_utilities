# browser_drive TODO

- (medium) Named keys and key combinations (`DriverPress("Enter")`, Ctrl+A) and mouse wheel, drag and double click.
- (low) A `DriverWaitStable` that looks at the canvas element only (or a region), so a blinking cursor elsewhere does not matter.
- (medium) A `DriverWaitForConsole` / `DriverWaitForEvent` that waits for a given console line instead of a fixed `DriverWait`.
- (medium) Several tabs, and the background worker of an extension as a target; Firefox extension pages (`webExtension.install` gives the add-on id, the moz-extension address is a random uuid).
- (medium) Chrome (branded, 137+) cannot load an extension from the command line: try `Extensions.loadUnpacked` over a pipe with `--enable-unsafe-extension-debugging`.
- (low) Safari (safaridriver speaks WebDriver classic over HTTP, not BiDi): not planned unless needed.
- (low) Mobile viewport emulation (touch, device pixel ratio) for CDP and BiDi.
