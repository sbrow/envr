package findr

import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"
import "core:strings"
import "core:testing"

TestEnv :: struct {
	temp_dir: string,
}

create_test_env :: proc() -> (env: TestEnv) {
	tmp, err := os.mkdir_temp("", "findr-test-*", context.allocator)
	if err != nil {
		log.error("Failed to create temp dir:", err)
		panic("Failed to create temp dir")
	}

	env.temp_dir = tmp
	return
}

destroy_test_env :: proc(env: ^TestEnv) {
	os.remove_all(env.temp_dir)
	delete(env.temp_dir)
}

create_dir :: proc(env: TestEnv, path: string) {
	full := join_path(env.temp_dir, path)
	defer delete(full)
	os.mkdir_all(full, os.Permissions_Default_Directory)
}

create_file :: proc(env: TestEnv, path: string, content: string = "") {
	full := join_path(env.temp_dir, path)
	defer delete(full)

	dir_end := strings.last_index(full, os.Path_Separator_String)
	if dir_end >= 0 {
		dir_path := full[:dir_end]
		os.mkdir_all(dir_path, os.Permissions_Default_Directory)
	}

	f, err := os.create(full)
	if err != nil {
		log.error("Failed to create file:", full, err)
		return
	}
	if len(content) > 0 {
		os.write_string(f, content)
	}
	os.close(f)
}

create_git_repo :: proc(env: TestEnv, path: string) {
	sub := join_path(path, ".git")
	defer delete(sub)
	create_dir(env, sub)
}

assert_output :: proc(
	t: ^testing.T,
	env: TestEnv,
	args: []string,
	opts: WalkOptions,
	expected: []string,
) {
	results := collect_results(env, args, opts)
	defer {
		for r in results {delete(r)}
		delete(results)
	}

	sorted_expected := make([dynamic]string, 0, len(expected))
	for e in expected {append(&sorted_expected, e)}
	defer delete(sorted_expected)

	sorted_actual := make([dynamic]string, 0, len(results))
	for a in results {append(&sorted_actual, a)}
	defer delete(sorted_actual)

	sort.quick_sort(sorted_expected[:])
	sort.quick_sort(sorted_actual[:])

	if len(sorted_expected) != len(sorted_actual) {
		testing.fail(t)
		log.error(
			fmt.tprintf("Expected %d results, got %d", len(sorted_expected), len(sorted_actual)),
		)
		log.error("Expected:", sorted_expected[:])
		log.error("Actual:  ", sorted_actual[:])
		return
	}

	for i in 0 ..< len(sorted_expected) {
		if sorted_expected[i] != sorted_actual[i] {
			testing.fail(t)
			log.error(fmt.tprintf("Mismatch at index %d", i))
			log.error("Expected:", sorted_expected[:])
			log.error("Actual:  ", sorted_actual[:])
			return
		}
	}
}

assert_output_empty :: proc(t: ^testing.T, env: TestEnv, args: []string, opts: WalkOptions) {
	results := collect_results(env, args, opts)
	defer {
		for r in results {delete(r)}
		delete(results)
	}
	if len(results) > 0 {
		testing.fail(t)
		log.error(fmt.tprintf("Expected no results, got %d:", len(results)))
		for r in results {
			log.error("  ", r)
		}
	}
}

collect_results :: proc(env: TestEnv, args: []string, opts: WalkOptions) -> [dynamic]string {
	results := make([dynamic]string)

	full_args := make([dynamic]string, 0, len(args) + 1, context.temp_allocator)
	append(&full_args, env.temp_dir)
	for a in args {append(&full_args, a)}

	thread_count := os.get_processor_core_count()
	walk(full_args[:], &results, opts, thread_count)

	for i in 0 ..< len(results) {
		r := results[i]
		if strings.has_prefix(r, env.temp_dir) {
			stripped := r[len(env.temp_dir):]
			if len(stripped) > 0 && stripped[0] == os.Path_Separator {
				stripped = stripped[1:]
			}
			new_r, _ := strings.clone(stripped)
			delete(r)
			results[i] = new_r
		}
	}

	return results
}

