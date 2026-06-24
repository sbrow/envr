package findr

import "core:os"
import "core:sort"
import "core:strings"
import "core:sys/linux"
import "core:testing"

// ============================================================================
// Gitignored file emission tests (emit ONLY gitignored files, descend everywhere)
// ============================================================================

@(test)
test_basic_gitignored :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/normal.txt")

	assert_output(t, env, nil, {}, {"repo/.env", "repo/secrets.env"})
}

@(test)
test_non_repo_not_scanned :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_dir(env, "norepo")
	create_file(env, "norepo/.gitignore", "*.env\n")
	create_file(env, "norepo/.env")

	assert_output_empty(t, env, nil, {})
}

@(test)
test_negation_pattern :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n!prod.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/prod.env")

	assert_output(t, env, nil, {}, {"repo/.env", "repo/secrets.env"})
}

@(test)
test_multiple_repos :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo1")
	create_file(env, "repo1/.gitignore", "*.env\n")
	create_file(env, "repo1/a.env")

	create_git_repo(env, "repo2")
	create_file(env, "repo2/.gitignore", "*.key\n")
	create_file(env, "repo2/secret.key")

	assert_output(t, env, nil, {}, {"repo1/a.env", "repo2/secret.key"})
}

@(test)
test_nested_repos :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "parent")
	create_file(env, "parent/.gitignore", "*.env\n")
	create_file(env, "parent/top.env")

	create_git_repo(env, "parent/child")
	create_file(env, "parent/child/.gitignore", "*.key\n")
	create_file(env, "parent/child/api.key")

	assert_output(t, env, nil, {}, {"parent/top.env", "parent/child/api.key"})
}

@(test)
test_nested_gitignore_read :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_dir(env, "repo/sub")
	create_file(env, "repo/sub/.gitignore", "*.txt\n")
	create_file(env, "repo/sub/secret.txt")
	create_file(env, "repo/sub/.env")

	assert_output(t, env, nil, {}, {"repo/sub/secret.txt", "repo/sub/.env"})
}

@(test)
test_nested_gitignore_negation :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.log\n")
	create_dir(env, "repo/sub")
	create_file(env, "repo/sub/.gitignore", "!important.log\n")
	create_file(env, "repo/sub/important.log")
	create_file(env, "repo/sub/debug.log")

	assert_output(t, env, nil, {}, {"repo/sub/debug.log"})
}

@(test)
test_multisegment_pattern :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "build/output.txt\n")
	create_dir(env, "repo/build")
	create_file(env, "repo/build/output.txt")
	create_file(env, "repo/build/other.txt")
	create_file(env, "repo/output.txt")

	assert_output(t, env, nil, {}, {"repo/build/output.txt"})
}

@(test)
test_no_gitignore_file :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.env")

	assert_output_empty(t, env, nil, {})
}

@(test)
test_empty_gitignore :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "\n\n# comment\n\n")
	create_file(env, "repo/.env")

	assert_output_empty(t, env, nil, {})
}

@(test)
test_multiple_search_dirs :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "dir1/repo")
	create_file(env, "dir1/repo/.gitignore", "*.env\n")
	create_file(env, "dir1/repo/a.env")
	create_file(env, "dir1/repo/normal.txt")

	create_git_repo(env, "dir2/repo")
	create_file(env, "dir2/repo/.gitignore", "*.env\n")
	create_file(env, "dir2/repo/b.env")

	dir1 := join_path(env.temp_dir, "dir1")
	defer delete(dir1)
	dir2 := join_path(env.temp_dir, "dir2")
	defer delete(dir2)

	results := make([dynamic]string)
	defer {
		for r in results {delete(r)}
		delete(results)
	}

	opts := WalkOptions{}
	thread_count := os.get_processor_core_count()
	walk({dir1, dir2}, &results, opts, thread_count)

	testing.expect_value(t, len(results), 2)

	actual := make([dynamic]string, 0, len(results))
	for r in results {
		stripped := r
		if strings.has_prefix(stripped, env.temp_dir) {
			stripped = stripped[len(env.temp_dir):]
			if len(stripped) > 0 && stripped[0] == os.Path_Separator {
				stripped = stripped[1:]
			}
		}
		append(&actual, stripped)
	}
	defer delete(actual)

	expected := []string{"dir1/repo/a.env", "dir2/repo/b.env"}

	sort.quick_sort(actual[:])
	sort.quick_sort(expected[:])

	for i in 0 ..< len(expected) {
		testing.expect_value(t, actual[i], expected[i])
	}
}

// ============================================================================
// Ignored directory recursion tests
// ============================================================================

@(test)
test_ignored_dir_descended :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "secrets/\n")
	create_dir(env, "repo/secrets")
	create_file(env, "repo/secrets/.env")
	create_file(env, "repo/secrets/api.key")

	// Ignored dir's contents are emitted AND descended into
	assert_output(t, env, nil, {}, {"repo/secrets/", "repo/secrets/.env", "repo/secrets/api.key"})
}

@(test)
test_nested_ignored_dir :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "build/\n")
	create_dir(env, "repo/build")
	create_dir(env, "repo/build/sub")
	create_file(env, "repo/build/output.txt")
	create_file(env, "repo/build/sub/deep.env")

	assert_output(
		t,
		env,
		nil,
		{},
		{"repo/build/", "repo/build/output.txt", "repo/build/sub/", "repo/build/sub/deep.env"},
	)
}

// ============================================================================
// Filter tests (excludes, pattern)
// ============================================================================

@(test)
test_excludes_prune_dirs :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_dir(env, "repo/vendor")
	create_file(env, "repo/vendor/lib.env")

	assert_output(t, env, nil, {excludes = {"vendor"}}, {"repo/.env"})
}

@(test)
test_pattern_filters_results :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n*.key\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/master.key")

	assert_output(t, env, nil, {pattern = "\\.env$"}, {"repo/.env", "repo/secrets.env"})
}

// ============================================================================
// Special file type tests
// ============================================================================

@(test)
test_fifo_emitted :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n*.fifo\n")

	fifo_path := join_path(env.temp_dir, "repo/test.fifo")
	defer delete(fifo_path)
	cpath := strings.clone_to_cstring(fifo_path)
	defer delete(cpath)
	linux.mknod(cpath, linux.S_IFIFO | linux.Mode{.IRUSR, .IWUSR}, 0)

	assert_output(t, env, nil, {pattern = "\\.fifo$"}, {"repo/test.fifo"})
}

