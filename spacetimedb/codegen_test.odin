#+build !js
package spacetimedb

import "core:os"
import "core:strings"
import "core:testing"

// The generated files of fixtures/generated are the output of the generator for the two schemas of fixtures/: a change of the generator shows up as a difference here (generate them again
// with `odin run spacetimedb/tool/generate -- --schema ... --package ... --library ../../.. --out ...`), and they have to compile and work.

// tests run in the folder odin_utilities, so the fixtures are found from this file
@(private = "file")
FIXTURES :: #directory + "fixtures/"

@(private = "file")
normalize :: proc(text: string) -> string {
    plain, _ := strings.remove_all(text, "\r", context.temp_allocator)
    return strings.trim_space(plain)
}

@(private = "file")
checkGolden :: proc(t: ^testing.T, schema: string, package_name: string, golden: string) {
    schema_json, schema_error := os.read_entire_file(schema, context.temp_allocator)
    golden_text, golden_error := os.read_entire_file(golden, context.temp_allocator)
    if schema_error != nil || golden_error != nil { testing.fail_now(t, "the fixture is missing") }
    source, ok := GenerateSource(string(schema_json), {package_name = package_name, library = "../../.."}, context.temp_allocator)
    testing.expect(t, ok)
    // the files may have been checked out with other line endings
    testing.expect(t, normalize(source) == normalize(string(golden_text)), "the generated file is not what the generator writes now")
}

@(test)
test_generator_output_is_the_committed_output :: proc(t: ^testing.T) {
    checkGolden(t, FIXTURES + "basic.schema.json", "basic", FIXTURES + "generated/basic/basic.odin")
    checkGolden(t, FIXTURES + "rich.schema.json", "rich", FIXTURES + "generated/rich/rich.odin")
}

@(test)
test_generator_rejects_what_is_not_a_schema :: proc(t: ^testing.T) {
    _, ok := GenerateSource("not json", {}, context.temp_allocator)
    testing.expect(t, !ok)
    _, empty := GenerateSource("{}", {}, context.temp_allocator)
    testing.expect(t, !empty)
}

@(test)
test_generated_packages_build_and_work :: proc(t: ^testing.T) {
    check, _, check_errors, check_error := os.process_exec({command = {"odin", "check", FIXTURES + "generated/basic", "-no-entry-point", "-strict-style", "-vet"}}, context.temp_allocator)
    testing.expectf(t, check_error == nil && check.success, "the generated basic package compiles: %s", string(check_errors))
    run, run_output, run_errors, run_error := os.process_exec({command = {"odin", "test", FIXTURES + "generated/rich", "-strict-style", "-vet", "-out:" + "generated_rich_test.exe"}}, context.temp_allocator)
    testing.expectf(t, run_error == nil && run.success, "the generated rich package passes its tests: %s %s", string(run_output), string(run_errors))
    os.remove("generated_rich_test.exe")
}
