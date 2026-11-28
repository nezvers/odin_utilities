package file_browser

// The Io of the platform the program runs on: the disk on a desktop, the chooser and the downloads of the browser in a web page (js_wasm32).
IoPlatform :: proc() -> Io {
    when ODIN_OS == .JS {
        return IoWeb()
    } else {
        return IoOs()
    }
}
