package file_browser

// Where the files are: a table of procs, so the browser works on the disk (`IoOs`, desktop), in the page of a web browser (`IoWeb`: no disk, the browser's own file chooser) and over a fake in a test.
// Nothing here allocates for the caller: names go into a Listing, bytes into a buffer the caller gives.

Error :: enum {
    NONE,
    NOT_FOUND,              // the file or the directory is not there
    DENIED,                 // no permission
    NOT_A_DIRECTORY,
    IS_A_DIRECTORY,
    TOO_BIG,                // the file does not fit the buffer the program gave
    NAME_EMPTY,             // nothing was typed or selected
    NAME_INVALID,           // a name with a separator or one of the characters that no file name has
    EXISTS,                 // the file exists and the person said no to replacing it
    UNSUPPORTED,            // this platform cannot do it
    FAILED,                 // the system said no and Odin does not say why
}

ErrorText :: proc(error: Error) -> string {
    switch error {
    case .NONE: return "no error"
    case .NOT_FOUND: return "not found"
    case .DENIED: return "permission denied"
    case .NOT_A_DIRECTORY: return "not a directory"
    case .IS_A_DIRECTORY: return "it is a directory"
    case .TOO_BIG: return "the file is too big for the buffer"
    case .NAME_EMPTY: return "no file name"
    case .NAME_INVALID: return "the file name has a character that is not allowed"
    case .EXISTS: return "the file exists"
    case .UNSUPPORTED: return "not supported here"
    case .FAILED: return "the system refused"
    }
    return "?"
}

// What the platform's own file chooser says (the browser of a web page)
PickStatus :: enum {
    PENDING,                // nothing yet: the person is choosing, or the file is being read
    READY,                  // a file was chosen and its bytes wait for `pick_take`
    CANCELLED,
    FAILED,
}

Io :: struct {
    user: rawptr,

    // desktop: the content of a directory, written with ListingAdd (the filter and the hidden rule are in the listing)
    list: proc(user: rawptr, dir: string, out: ^Listing) -> Error,
    // the bytes of a file into `buffer`: TOO_BIG when it does not fit (nothing is read then)
    read: proc(user: rawptr, path: string, buffer: []u8) -> (count: int, err: Error),
    // create or replace a file
    write: proc(user: rawptr, path: string, data: []u8) -> Error,
    // does something exist at that path, and is it a directory
    stat: proc(user: rawptr, path: string) -> (exists: bool, directory: bool),
    // the directory to browse first when nothing is remembered (home or the working directory), written into `buffer`
    start: proc(user: rawptr, buffer: []u8) -> string,

    // the platform's own chooser (optional: all five set, or none). With these the browser does not show a dialog of its own: a program that runs in a web page cannot see the disk.
    pick_start: proc(user: rawptr, accept: string),                     // open the chooser, `accept` is ".png,.jpg" or ""
    pick_poll: proc(user: rawptr) -> PickStatus,
    pick_name: proc(user: rawptr, buffer: []u8) -> string,            // the name of the chosen file
    pick_take: proc(user: rawptr, buffer: []u8) -> (count: int, err: Error),   // the bytes of it into `buffer`; TOO_BIG when they do not fit (the file stays for a bigger buffer)
    download: proc(user: rawptr, name: string, data: []u8) -> Error,  // hand a file to the person (the browser saves it in its downloads folder)
}

// The platform has its own chooser: the browser does not list directories
IoNative :: proc(io: ^Io) -> bool {
    return io.pick_start != nil
}
