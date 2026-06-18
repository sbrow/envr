package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "findr"

SshKeyPair :: struct {
	Private: string `json:"private"`,
	Public:  string `json:"public"`,
}

ScanConfig :: struct {
	Matcher: string `json:"matcher"`,
	Exclude: [dynamic]string `json:"exclude"`,
	Include: [dynamic]string `json:"include"`,
}

Config :: struct {
	Keys:        [dynamic]SshKeyPair `json:"keys"`,
	ScanConfig:  ScanConfig `json:"scan"`,
	config_path: string `json:"-"`,
}

load_config :: proc(config_path: string, allocator := context.allocator) -> (Config, bool) {
	// TODO: Should we use context.allocator + defer delete()?
	data, read_err := os.read_entire_file_from_path(config_path, context.temp_allocator)
	if read_err != nil {
		fmt.println("No config file found. Please run `envr init` to generate one.")
		return Config{}, false
	}

	cfg: Config
	err := json.unmarshal(data, &cfg, .JSON5, allocator)
	if err != nil {
		fmt.printf("Error parsing config: %v\n", err)
		return Config{}, false
	}
	cfg.config_path = config_path

	return cfg, true
}

default_config_path :: proc(home: string, allocator := context.allocator) -> string {
	path, err := filepath.join([]string{home, ".envr", "config.json"}, allocator)
	if err != nil {
		panic("Ran out of memory when building config path")
	}
	return path
}

delete_config :: proc(cfg: ^Config, allocator := context.allocator) {
	for key in cfg.Keys {
		delete(key.Private, allocator)
		delete(key.Public, allocator)
	}
	delete(cfg.Keys)

	delete(cfg.ScanConfig.Matcher, allocator)

	for exclude in cfg.ScanConfig.Exclude {
		delete(exclude, allocator)
	}
	delete(cfg.ScanConfig.Exclude)

	for include in cfg.ScanConfig.Include {
		delete(include, allocator)
	}
	delete(cfg.ScanConfig.Include)
}

save_config :: proc(cfg: Config, force: bool = false) -> bool {
	config_dir := envr_dir(cfg.config_path)

	if !os.exists(config_dir) {
		mkdir_err := os.make_directory(config_dir)
		if mkdir_err != nil {
			fmt.printf("Error creating %s directory: %v\n", config_dir, mkdir_err)
			return false
		}
	}

	if os.exists(cfg.config_path) && !force {
		info, stat_err := os.stat(cfg.config_path, context.allocator)
		if stat_err == nil {
			defer os.file_info_delete(info, context.allocator)
			if info.size > 0 {
				fmt.println("Config file already exists. Run again with --force to reinitialize.")
				return false
			}
		}
	}

	data, marshal_err := json.marshal(cfg, {pretty = true, use_spaces = true, spaces = 2})
	if marshal_err != nil {
		fmt.printf("Error marshaling config: %v\n", marshal_err)
		return false
	}
	defer delete(data)

	write_err := os.write_entire_file(cfg.config_path, data)
	if write_err != nil {
		fmt.printf("Error writing config: %v\n", write_err)
		return false
	}

	return true
}

// Caller is responsible for calling delete_config()
new_config :: proc(
	private_key_paths: []string,
	cfg_path: string = "~/.envr/config.json",
) -> Config {
	keys := make([dynamic]SshKeyPair, 0, len(private_key_paths))
	for priv in private_key_paths {
		// TODO: Is this bad?
		priv_key := strings.clone(priv)
		pub, _ := strings.concatenate([]string{priv_key, ".pub"})
		append(&keys, SshKeyPair{Private = priv_key, Public = pub})
	}

	exclude := make([dynamic]string, 0, 4)
	append(&exclude, strings.clone("*\\.envrc"))
	append(&exclude, strings.clone("\\.local/"))
	append(&exclude, strings.clone("node_modules"))
	append(&exclude, strings.clone("vendor"))

	include := make([dynamic]string, 0, 1)
	append(&include, strings.clone("~"))

	scan_cfg := ScanConfig {
		Matcher = strings.clone("\\.env"),
		Exclude = exclude,
		Include = include,
	}

	return Config{Keys = keys, ScanConfig = scan_cfg, config_path = cfg_path}
}

find_ssh_private_keys :: proc() -> (keys: [dynamic]string, ok: bool) {
	home, home_err := os.user_home_dir(context.allocator)
	if home_err != nil {
		fmt.printf("Error getting home dir: %v\n", home_err)
		return
	}

	ssh_dir, join_err := filepath.join([]string{home, ".ssh"})
	if join_err != nil {
		fmt.printf("Error building ssh path: %v\n", join_err)
		return
	}

	entries, dir_err := os.read_all_directory_by_path(ssh_dir, context.allocator)
	if dir_err != nil {
		fmt.printf("Could not read ~/.ssh directory: %v\n", dir_err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		name := entry.name
		if entry.type == .Directory {
			continue
		}
		if strings.has_suffix(name, ".pub") {
			continue
		}
		if strings.contains(name, "known_hosts") {
			continue
		}
		if strings.contains(name, "config") {
			continue
		}

		full_path, _ := filepath.join([]string{ssh_dir, name})
		if !is_ed25519_key(full_path) {
			continue
		}
		append(&keys, full_path)
	}

	ok = true
	return
}

find_git_roots :: proc(cfg: Config) -> (roots: [dynamic]string, ok: bool) {
	paths := search_paths(cfg)
	findr.find_repos(paths[:], &roots, os.get_processor_core_count())
	ok = true
	return
}

search_paths :: proc(cfg: Config) -> (paths: [dynamic]string) {
	// TODO: Is this okay?
	// TODO: handle error
	home, _ := os.user_home_dir(context.temp_allocator)

	for include in cfg.ScanConfig.Include {
		// TODO: Do we need to manually expand ~/ in odin?
		expanded, _ := strings.replace(include, "~", home, 1)
		if filepath.is_abs(expanded) {
			append(&paths, expanded)
		} else {
			defer delete(expanded)
			resolved, err := filepath.abs(expanded)
			if err == nil {
				append(&paths, resolved)
			}
		}
	}
	return
}

envr_dir :: proc(config_path: string) -> string {
	return filepath.dir(config_path)
}

// User is responsible for freeing the path
data_path :: proc(config_path: string, allocator := context.allocator) -> string {
	path, _ := filepath.join([]string{envr_dir(config_path), "data.envr"}, allocator)
	return path
}

