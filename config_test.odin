package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:testing"

home_mutex: sync.Mutex

@(test)
test_new_config_single_key :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect(t, len(cfg.Keys) == 1, "should have 1 key")
	testing.expect(t, cfg.Keys[0].Private == "/home/user/.ssh/id_ed25519", "Private path mismatch")
	testing.expect(
		t,
		cfg.Keys[0].Public == "/home/user/.ssh/id_ed25519.pub",
		"Public path mismatch",
	)
}

@(test)
test_new_config_multiple_keys :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519", "/home/user/.ssh/id_rsa"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect(t, len(cfg.Keys) == 2, "should have 2 keys")
	testing.expect(t, cfg.Keys[0].Private == "/home/user/.ssh/id_ed25519")
	testing.expect(t, cfg.Keys[1].Private == "/home/user/.ssh/id_rsa")
}

@(test)
test_new_config_empty_keys :: proc(t: ^testing.T) {
	paths: []string
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect(t, len(cfg.Keys) == 0, "should have 0 keys")
}

@(test)
test_new_config_scan_defaults :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect(t, cfg.ScanConfig.Matcher == "\\.env", "matcher should be \\.env")
	testing.expect(t, len(cfg.ScanConfig.Exclude) == 4, "should have 4 exclude patterns")
	testing.expect(t, len(cfg.ScanConfig.Include) == 1, "should have 1 include path")
	testing.expect(t, cfg.ScanConfig.Include[0] == "~", "include should be ~")
}

@(test)
test_new_config_exclude_patterns :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	expected := []string{"*\\.envrc", "\\.local/", "node_modules", "vendor"}
	for i in 0 ..< len(expected) {
		testing.expect(t, cfg.ScanConfig.Exclude[i] == expected[i])
	}
}

@(test)
test_save_load_config_roundtrip :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/envr-test-cfg-rt-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	cfgPath, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect(t, err == nil, "cfgPath should build successfully")

	cfg := new_config([]string{"/home/user/.ssh/id_ed25519"}, cfgPath)
	defer delete_config(&cfg)

	testing.expect(t, save_config(cfg, force = true), "save should succeed")

	loaded, ok := load_config(cfg.config_path)
	testing.expect(t, ok, "load should succeed")
	if !ok do return
	defer delete_config(&loaded)

	testing.expect(t, len(loaded.Keys) == 1, "should have 1 key")
	testing.expect(t, loaded.Keys[0].Private == "/home/user/.ssh/id_ed25519")
	testing.expect(t, loaded.Keys[0].Public == "/home/user/.ssh/id_ed25519.pub")
	testing.expect(t, loaded.ScanConfig.Matcher == "\\.env")
	testing.expect(t, len(loaded.ScanConfig.Exclude) == 4)
	testing.expect(t, len(loaded.ScanConfig.Include) == 1)
	testing.expect(t, loaded.ScanConfig.Include[0] == "~")
}

@(test)
test_load_config_missing :: proc(t: ^testing.T) {
	_, ok := load_config("/tmp/envr-test-cfg-nonexistent/config.json")
	testing.expect(t, !ok, "missing config should return false")
}

@(test)
test_save_config_no_clobber :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/envr-test-cfg-noclobber-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	cfgPath, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect(t, err == nil, "cfgPath should build successfully")

	cfg := new_config([]string{"/home/user/.ssh/key1"}, cfgPath)
	defer delete_config(&cfg)
	testing.expect(t, save_config(cfg, force = true), "first save should succeed")

	cfg2 := new_config([]string{"/home/user/.ssh/key2"}, cfgPath)
	defer delete_config(&cfg2)
	testing.expect(t, !save_config(cfg2), "second save without force should fail")
}

@(test)
test_save_config_force_overwrites :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/envr-test-cfg-force-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	cfgPath, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect(t, err == nil, "cfgPath should build successfully")

	cfg := new_config([]string{"/home/user/.ssh/key1"}, cfgPath)
	defer delete_config(&cfg)
	testing.expect(t, save_config(cfg, force = true), "first save should succeed")

	cfg2 := new_config([]string{"/home/user/.ssh/key2"}, cfgPath)
	defer delete_config(&cfg2)
	testing.expect(t, save_config(cfg2, force = true), "force save should overwrite")

	loaded, ok := load_config(cfgPath)
	testing.expect(t, ok, "load should succeed")
	if !ok do return
	defer delete_config(&loaded)

	testing.expect(t, len(loaded.Keys) == 1, "should have 1 key")
	testing.expect(
		t,
		loaded.Keys[0].Private == "/home/user/.ssh/key2",
		"should be the overwritten key",
	)
}

@(test)
test_envr_dir :: proc(t: ^testing.T) {
	dir := envr_dir("/tmp/envr-fake-home-envrdir/.envr/config.json")
	testing.expectf(t, strings.has_suffix(dir, ".envr"), "dir should end with .envr, got %s", dir)
	testing.expectf(
		t,
		strings.contains(dir, "envr-fake-home-envrdir"),
		"dir should contain home dir, got %s",
		dir,
	)
}

@(test)
test_data_encrypted_path :: proc(t: ^testing.T) {
	p := data_encrypted_path("/tmp/envr-fake-home-datapath/config.json")
	defer delete(p)
	testing.expectf(t, strings.has_suffix(p, "data.envr"), "should end with data.envr, got %s", p)
	testing.expectf(t, strings.contains(p, ".envr"), "should contain .envr dir, got %s", p)
}

@(test)
test_search_paths_expands_tilde :: proc(t: ^testing.T) {
	sync.mutex_lock(&home_mutex)
	defer sync.mutex_unlock(&home_mutex)

	old_home := os.get_env("HOME", context.temp_allocator)
	defer {
		if old_home != "" {
			os.set_env("HOME", old_home)
		}
	}

	os.set_env("HOME", "/tmp/envr-fake-home-search")

	cfg := Config {
		ScanConfig = ScanConfig{Include = make([dynamic]string, 0, 1)},
	}
	defer delete(cfg.ScanConfig.Include)
	append(&cfg.ScanConfig.Include, "~")

	paths := search_paths(cfg)
	defer delete(paths)
	for path in paths {
		defer delete(path)
	}

	testing.expect(t, len(paths) == 1, "should have 1 path")
	if len(paths) > 0 {
		testing.expectf(
			t,
			strings.contains(paths[0], "envr-fake-home-search"),
			"should expand ~ to home, got %s",
			paths[0],
		)
		testing.expect(t, !strings.contains(paths[0], "~"), "should not contain literal ~")
	}
}

