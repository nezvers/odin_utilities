package file_browser

import "core:slice"

// The content of one directory in caller memory: `entries` (the rows) and `names` (the bytes of their names). A directory with more entries than fit is cut and `truncated` says so: fail, not grow.
// Directories sort first, then files, each by name without regard to case.

Entry :: struct {
    name: string,               // points into Listing.names
    directory: bool,
    size: i64,                  // bytes, 0 for a directory
}

Listing :: struct {
    entries: []Entry,
    names: []u8,
    count: int,
    names_used: int,
    truncated: bool,            // something did not fit
    filter: Filter,             // files that do not pass are not added (directories always are)
    show_hidden: bool,          // names that start with a dot are skipped unless this is set
    skipped: int,               // how many entries the filter and the hidden rule left out
}

ListingInit :: proc(listing: ^Listing, entries: []Entry, names: []u8) {
    listing^ = {entries = entries, names = names}
}

// Empty, keeping the filter and the memory
ListingClear :: proc(listing: ^Listing) {
    listing.count, listing.names_used, listing.skipped = 0, 0, 0
    listing.truncated = false
}

// Add one entry (what an `Io.list` does for each name). False when it was left out: it does not pass the filter, it is hidden, or there is no room (then `truncated` is set).
ListingAdd :: proc(listing: ^Listing, name: string, directory: bool, size: i64 = 0) -> bool {
    if len(name) == 0 { return false }
    if !listing.show_hidden && name[0] == '.' {
        listing.skipped += 1
        return false
    }
    if !directory && !FilterMatches(listing.filter, name) {
        listing.skipped += 1
        return false
    }
    if listing.count >= len(listing.entries) || listing.names_used + len(name) > len(listing.names) {
        listing.truncated = true
        return false
    }
    copy(listing.names[listing.names_used:], name)
    listing.entries[listing.count] = {name = string(listing.names[listing.names_used:][:len(name)]), directory = directory, size = size}
    listing.count += 1
    listing.names_used += len(name)
    return true
}

ListingSort :: proc(listing: ^Listing) {
    slice.sort_by(listing.entries[:listing.count], proc(a: Entry, b: Entry) -> bool {
        if a.directory != b.directory { return a.directory }
        return compareFold(a.name, b.name) < 0
    })
}

// The row of a name (exact), -1 when there is none
ListingFind :: proc(listing: ^Listing, name: string) -> int {
    for i in 0 ..< listing.count {
        if listing.entries[i].name == name { return i }
    }
    return -1
}
