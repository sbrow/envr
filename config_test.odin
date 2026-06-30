#+test
package main

import "core:fmt"
import "core:mem"
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

	testing.expect_value(t, len(cfg.keys), 1)
	testing.expect_value(t, cfg.keys[0].private, "/home/user/.ssh/id_ed25519")
	testing.expect_value(t, cfg.keys[0].public, "/home/user/.ssh/id_ed25519.pub")
}

@(test)
test_new_config_multiple_keys :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519", "/home/user/.ssh/id_rsa"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect_value(t, len(cfg.keys), 2)
	testing.expect_value(t, cfg.keys[0].private, "/home/user/.ssh/id_ed25519")
	testing.expect_value(t, cfg.keys[1].private, "/home/user/.ssh/id_rsa")
}

@(test)
test_new_config_empty_keys :: proc(t: ^testing.T) {
	paths: []string
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect_value(t, len(cfg.keys), 0)
}

@(test)
test_new_config_scan_defaults :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	testing.expect_value(t, cfg.scan_config.matcher, "\\.env")
	testing.expect_value(t, len(cfg.scan_config.exclude), 4)
	testing.expect_value(t, len(cfg.scan_config.include), 1)
	testing.expect_value(t, cfg.scan_config.include[0], "~")
}

@(test)
test_new_config_exclude_patterns :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(&cfg)

	expected := []string{"*\\.envrc", "\\.local/", "node_modules", "vendor"}
	for i in 0 ..< len(expected) {
		testing.expect_value(t, cfg.scan_config.exclude[i], expected[i])
	}
}

@(test)
test_save_load_config_roundtrip :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-cfg-rt-*")
	defer os.remove_all(base)

	cfgPath, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect_value(t, err, nil)

	cfg := new_config([]string{"/home/user/.ssh/id_ed25519"}, cfgPath)
	defer delete_config(&cfg)

	testing.expect(t, save_config(cfg, force = true), "save should succeed")

	loaded, ok := load_config(cfg.config_path)
	testing.expect(t, ok, "load should succeed")
	if !ok do return
	defer delete_config(&loaded)

	testing.expect_value(t, len(loaded.keys), 1)
	testing.expect_value(t, loaded.keys[0].private, "/home/user/.ssh/id_ed25519")
	testing.expect_value(t, loaded.keys[0].public, "/home/user/.ssh/id_ed25519.pub")
	testing.expect_value(t, loaded.scan_config.matcher, "\\.env")
	testing.expect_value(t, len(loaded.scan_config.exclude), 4)
	testing.expect_value(t, len(loaded.scan_config.include), 1)
	testing.expect_value(t, loaded.scan_config.include[0], "~")
}

@(test)
test_load_config_missing :: proc(t: ^testing.T) {
	_, ok := load_config("/tmp/envr-test-cfg-nonexistent/config.json")
	testing.expect(t, !ok, "missing config should return false")
}

@(test)
test_save_config_no_clobber :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-cfg-noclobber-*")
	defer os.remove_all(base)

	cfgPath, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect_value(t, err, nil)

	cfg := new_config([]string{"/home/user/.ssh/key1"}, cfgPath)
	defer delete_config(&cfg)
	testing.expect(t, save_config(cfg, force = true), "first save should succeed")

	cfg2 := new_config([]string{"/home/user/.ssh/key2"}, cfgPath)
	defer delete_config(&cfg2)
	testing.expect(t, !save_config(cfg2), "second save without force should fail")
}

@(test)
test_save_config_force_overwrites :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-cfg-force-*")
	defer os.remove_all(base)

	cfgPath, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect_value(t, err, nil)

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

	testing.expect_value(t, len(loaded.keys), 1)
	testing.expect_value(t, loaded.keys[0].private, "/home/user/.ssh/key2")
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
test_data_path :: proc(t: ^testing.T) {
	p := data_path("/tmp/envr-fake-home-datapath/config.json")
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
		scan_config = ScanConfig{include = make([dynamic]string, 0, 1)},
	}
	append(&cfg.scan_config.include, "~")
	defer delete(cfg.scan_config.include)

	paths := search_paths(cfg, context.temp_allocator)

	testing.expect_value(t, len(paths), 1)
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

@(test)
test_search_paths_no_leak :: proc(t: ^testing.T) {
	cfg := Config {
		scan_config = ScanConfig{include = make([dynamic]string, 0, 1)},
	}
	defer delete(cfg.scan_config.include)
	append(&cfg.scan_config.include, "/tmp")

	_ = search_paths(cfg, context.allocator)
}

