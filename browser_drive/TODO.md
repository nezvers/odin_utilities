# browser_drive TODO

- (medium) Named keys and key combinations (`DriverPress("Enter")`, Ctrl+A) and mouse wheel, drag and double click.
- (medium) A `DriverWaitForConsole` / `DriverWaitForEvent` that waits for a given console line instead of a fixed `DriverWait`.
- (medium) Several tabs, and an extension page (a `browser_extension` options page or background worker) as a target.
- (low) Safari (safaridriver speaks WebDriver classic over HTTP, not BiDi): not planned unless needed.
- (low) Mobile viewport emulation (touch, device pixel ratio) for CDP and BiDi.
