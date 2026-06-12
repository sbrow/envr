package main

import "core:testing"

@(test)
test_new_config_single_key :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(cfg)

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
	defer delete_config(cfg)

	testing.expect(t, len(cfg.Keys) == 2, "should have 2 keys")
	testing.expect(t, cfg.Keys[0].Private == "/home/user/.ssh/id_ed25519")
	testing.expect(t, cfg.Keys[1].Private == "/home/user/.ssh/id_rsa")
}

@(test)
test_new_config_empty_keys :: proc(t: ^testing.T) {
	paths: []string
	cfg := new_config(paths)
	defer delete_config(cfg)

	testing.expect(t, len(cfg.Keys) == 0, "should have 0 keys")
}

@(test)
test_new_config_scan_defaults :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(cfg)

	testing.expect(t, cfg.ScanConfig.Matcher == "\\.env", "matcher should be \\.env")
	testing.expect(t, len(cfg.ScanConfig.Exclude) == 4, "should have 4 exclude patterns")
	testing.expect(t, len(cfg.ScanConfig.Include) == 1, "should have 1 include path")
	testing.expect(t, cfg.ScanConfig.Include[0] == "~", "include should be ~")
}

@(test)
test_new_config_exclude_patterns :: proc(t: ^testing.T) {
	paths := []string{"/home/user/.ssh/id_ed25519"}
	cfg := new_config(paths)
	defer delete_config(cfg)

	expected := []string{"*\\.envrc", "\\.local/", "node_modules", "vendor"}
	for i in 0 ..< len(expected) {
		testing.expect(t, cfg.ScanConfig.Exclude[i] == expected[i])
	}
}

