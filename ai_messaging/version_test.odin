#+build !js
package ai_messaging

import "core:strings"
import "core:testing"

@(test)
VersionTextTest :: proc(t: ^testing.T) {
    line: string = VersionText()
    testing.expect(t, strings.has_prefix(line, "amsg "), "the line starts with the name")
    testing.expect(t, strings.contains(line, VERSION), "and has the version")
    testing.expect(t, strings.contains(line, "commit "), "and says which commit")
}

@(test)
VersionJsonFieldTest :: proc(t: ^testing.T) {
    // the shape of an answer of the commits API: the sha, then the commit with its author, date and message
    body: string = `[{"sha":"0123456789abcdef0123456789abcdef01234567","commit":{"author":{"name":"x","date":"2026-11-19T10:15:00Z"},"message":"first line\nsecond \"quoted\" line"}}]`
    testing.expect_value(t, jsonField(body, "\"sha\""), "0123456789abcdef0123456789abcdef01234567")
    author: int = strings.index(body, "\"author\"")
    testing.expect_value(t, jsonField(body[author:], "\"date\""), "2026-11-19T10:15:00Z")
    message: string = jsonField(body, "\"message\"")
    testing.expect_value(t, firstLine(message), "first line")
    testing.expect(t, strings.contains(message, "second \"quoted\" line"))
    testing.expect_value(t, jsonField(body, "\"nothing\""), "")
}
