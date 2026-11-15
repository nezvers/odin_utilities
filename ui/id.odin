package ui

// Element ids. The hash is the one of Clay (https://github.com/nicbarker/clay, MIT, Nic Barker): a Jenkins style one at a time hash with a seed.
// The seed is the id of the element that holds the name, so "Ok" in two panels are two different ids. 0 is reserved for "no id".

IdFromString :: proc(text: string, seed: Id = 0) -> Id {
    hash: u32 = u32(seed)
    for i in 0 ..< len(text) {
        hash += u32(text[i])
        hash += hash << 10
        hash ~= hash >> 6
    }
    hash += hash << 3
    hash ~= hash >> 11
    hash += hash << 15
    return Id(hash + 1)
}

// An id from a number (the n-th item of a list): `IdFromIndex(i, list_id)`
IdFromIndex :: proc(index: u32, seed: Id = 0) -> Id {
    hash: u32 = u32(seed)
    hash += index + 48
    hash += hash << 10
    hash ~= hash >> 6
    hash += hash << 3
    hash ~= hash >> 11
    hash += hash << 15
    return Id(hash + 1)
}

// "Save##slot2" is shown as "Save", the whole string is hashed: the same text in two places gets different ids by adding "##" and something.
// "##hidden" shows nothing. Returns the text to show.
IdSplitName :: proc(name: string) -> (shown: string) {
    for i in 0 ..< len(name) - 1 {
        if name[i] == '#' && name[i + 1] == '#' {
            return name[:i]
        }
    }
    return name
}
