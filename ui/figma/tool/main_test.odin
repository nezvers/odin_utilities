package main

import "core:os"
import "core:testing"

@(test)
test_the_tool_writes_the_source_and_refuses_bad_input :: proc(t: ^testing.T) {
    out :: "figma_tool_test_output.odin"
    defer os.remove(out)
    testing.expect_value(t, run({"--in", #directory + "../fixtures/login.json", "--package", "shown", "--out", out}), 0)
    written, read_error := os.read_entire_file(out, context.temp_allocator)
    testing.expect(t, read_error == nil && len(written) > 100)
    testing.expect_value(t, run({}), 1)
    testing.expect_value(t, run({"--in", "no_such_file.json"}), 1)
    testing.expect_value(t, run({"--in", #directory + "../fixtures/login.json", "--frame", "Nothing"}), 1)
    testing.expect_value(t, run({"--nonsense"}), 1)
}
