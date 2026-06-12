package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"

SshKeyPair :: struct {
	Private: string `json:"private"`,
	Public:  string `json:"public"`,
}

ScanConfig :: struct {
	Matcher: string   `json:"matcher"`,
	Exclude: []string `json:"exclude"`,
	Include: []string `json:"include"`,
}

Config :: struct {
	Keys:       []SshKeyPair `json:"keys"`,
	ScanConfig: ScanConfig   `json:"scan"`,
}

load_config :: proc() -> (Config, bool) {
	home, home_err := os.user_home_dir(context.allocator)
	if home_err != nil {
		fmt.printf("Error getting home dir: %v\n", home_err)
		return Config{}, false
	}
	config_path, join_err := filepath.join([]string{home, ".envr", "config.json"})
	if join_err != nil {
		return Config{}, false
	}

	data, read_err := os.read_entire_file_from_path(config_path, context.allocator)
	if read_err != nil {
		fmt.println("No config file found. Please run `envr init` to generate one.")
		return Config{}, false
	}

	cfg: Config
	err := json.unmarshal(data, &cfg)
	if err != nil {
		fmt.printf("Error parsing config: %v\n", err)
		return Config{}, false
	}

	return cfg, true
}

envr_dir :: proc() -> string {
	home, _ := os.user_home_dir(context.allocator)
	dir, _ := filepath.join([]string{home, ".envr"})
	return dir
}

data_age_path :: proc() -> string {
	dir := envr_dir()
	path, _ := filepath.join([]string{dir, "data.age"})
	return path
}
