package browser_drive

import "core:os"

Browser :: enum {
    CHROME,                 // Chrome, DevTools protocol
    EDGE,                   // Edge, the same protocol (it is Chromium)
    FIREFOX,                // Firefox, WebDriver BiDi
}

Protocol :: enum {
    CDP,                    // the Chrome DevTools Protocol: JSON messages over a WebSocket, one per tab
    BIDI,                   // WebDriver BiDi, the standard that Firefox speaks
}

BrowserProtocol :: proc(browser: Browser) -> Protocol {
    return .BIDI if browser == .FIREFOX else .CDP
}

BrowserName :: proc(browser: Browser) -> string {
    switch browser {
    case .CHROME: return "chrome"
    case .EDGE: return "edge"
    case .FIREFOX: return "firefox"
    }
    return ""
}

// Where each browser is installed, tried in this order
@(private)
CHROME_PATHS := [?]string{
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
}

@(private)
EDGE_PATHS := [?]string{
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
    "/usr/bin/microsoft-edge",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
}

@(private)
FIREFOX_PATHS := [?]string{
    "C:/Program Files/Mozilla Firefox/firefox.exe",
    "C:/Program Files (x86)/Mozilla Firefox/firefox.exe",
    "/usr/bin/firefox",
    "/Applications/Firefox.app/Contents/MacOS/firefox",
}

@(private)
browserPaths :: proc(browser: Browser) -> []string {
    switch browser {
    case .CHROME: return CHROME_PATHS[:]
    case .EDGE: return EDGE_PATHS[:]
    case .FIREFOX: return FIREFOX_PATHS[:]
    }
    return nil
}

// The executable of a browser, "" when it is not installed
BrowserFind :: proc(browser: Browser) -> string {
    for path in browserPaths(browser) {
        if os.exists(path) { return path }
    }
    return ""
}
