package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_scan_path_finds_gitignored_env_files :: proc(t: ^testing.T) {
	feats := check_features()
	testing.expect(t, cant_scan(feats) == false)

	base := fmt.aprintf("/tmp/envr-scan-test-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	git_init := os.Process_Desc {
		command     = []string{"git", "-c", "advice.defaultBranchName=false", "init"},
		working_dir = base,
		stdout      = os.stderr,
		stderr      = os.stderr,
	}
	p, err := os.process_start(git_init)
	if err != nil {
		return
	}
	_, wait_err := os.process_wait(p)
	if wait_err != nil {
		return
	}

	gitignore_path := fmt.aprintf("%s/.gitignore", base)
	_ = os.write_entire_file(gitignore_path, ".env*\n")

	_ = os.write_entire_file(fmt.aprintf("%s/.env", base), "SECRET=1")
	_ = os.write_entire_file(fmt.aprintf("%s/.env.testing", base), "TEST=1")
	_ = os.write_entire_file(fmt.aprintf("%s/config.yaml", base), "key: value")

	cfg := Config {
		ScanConfig = ScanConfig{Matcher = "\\.env", Exclude = []string{}, Include = []string{}},
	}

	results, ok := scan_path(base, cfg)
	defer delete(results)
	testing.expect(t, ok, "scan_path should succeed")

	found_env := false
	found_testing := false
	found_config := false

	for path in results {
		_, filename := filepath.split(path)
		if filename == ".env" {
			found_env = true
		}
		if filename == ".env.testing" {
			found_testing = true
		}
		if filename == "config.yaml" {
			found_config = true
		}
	}

	testing.expect(t, found_env, "should find .env (gitignored)")
	testing.expect(t, found_testing, "should find .env.testing (gitignored)")
	testing.expect(t, !found_config, "should NOT find config.yaml (not gitignored)")
}

@(test)
test_scan_path_empty_dir :: proc(t: ^testing.T) {
	feats := check_features()
	testing.expect(t, cant_scan(feats) == false)

	base := fmt.aprintf("/tmp/envr-scan-empty-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	cfg := Config {
		ScanConfig = ScanConfig{Matcher = "\\.env", Exclude = []string{}, Include = []string{}},
	}

	results, ok := scan_path(base, cfg)
	defer delete(results)
	testing.expect(t, ok, "scan_path should succeed")
	testing.expect(t, len(results) == 0, fmt.aprintf("expected 0 results, got %d", len(results)))
}

