package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "findr"

Config :: struct {
	keys:        [dynamic]SshKeyPair `json:"keys"`,
	scan_config: ScanConfig `json:"scan"`,
	config_path: string `json:"-"`,
}

SshKeyPair :: struct {
	private: string `json:"private"`,
	public:  string `json:"public"`,
}

ScanConfig :: struct {
	matcher: string `json:"matcher"`,
	exclude: [dynamic]string `json:"exclude"`,
	include: [dynamic]string `json:"include"`,
}

load_config :: proc(config_path: string, allocator := context.allocator) -> (Config, bool) {
	// TODO: Should we use context.allocator + defer delete()?
	data, read_err := os.read_entire_file_from_path(config_path, context.temp_allocator)
	if read_err != nil {
		fmt.eprintln("No config file found. Please run `envr init` to generate one.")
		return Config{}, false
	}

	cfg: Config
	err := json.unmarshal(data, &cfg, .JSON5, allocator)
	if err != nil {
		fmt.eprintf("Error parsing config: %v\n", err)
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
	for key in cfg.keys {
		delete(key.private, allocator)
		delete(key.public, allocator)
	}
	delete(cfg.keys)

	delete(cfg.scan_config.matcher, allocator)

	for exclude in cfg.scan_config.exclude {
		delete(exclude, allocator)
	}
	delete(cfg.scan_config.exclude)

	for include in cfg.scan_config.include {
		delete(include, allocator)
	}
	delete(cfg.scan_config.include)
}

save_config :: proc(cfg: Config, force: bool = false) -> bool {
	config_dir := envr_dir(cfg.config_path)

	if !os.exists(config_dir) {
		mkdir_err := os.make_directory(config_dir)
		if mkdir_err != nil {
			fmt.eprintf("Error creating %s directory: %v\n", config_dir, mkdir_err)
			return false
		}
	}

	if os.exists(cfg.config_path) && !force {
		info, stat_err := os.stat(cfg.config_path, context.temp_allocator)
		if stat_err == nil {
			defer os.file_info_delete(info, context.temp_allocator)
			if info.size > 0 {
				fmt.eprintln("Config file already exists. Run again with --force to reinitialize.")
				return false
			}
		}
	}

	data, marshal_err := json.marshal(
		cfg,
		{pretty = true, use_spaces = true, spaces = 2},
		context.temp_allocator,
	)
	if marshal_err != nil {
		fmt.eprintf("Error marshaling config: %v\n", marshal_err)
		return false
	}

	write_err := os.write_entire_file(cfg.config_path, data)
	if write_err != nil {
		fmt.eprintf("Error writing config: %v\n", write_err)
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
		append(&keys, SshKeyPair{private = priv_key, public = pub})
	}

	// If we don't clone the strings, the cleanup semantics differ for Db created
	// configs vs user created configs.
	exclude := make([dynamic]string, 0, 4)
	append(&exclude, strings.clone("*\\.envrc"))
	append(&exclude, strings.clone("\\.local/"))
	append(&exclude, strings.clone("node_modules"))
	append(&exclude, strings.clone("vendor"))

	include := make([dynamic]string, 0, 1)
	append(&include, strings.clone("~"))

	scan_cfg := ScanConfig {
		matcher = strings.clone("\\.env"),
		exclude = exclude,
		include = include,
	}

	return Config{keys = keys, scan_config = scan_cfg, config_path = cfg_path}
}

find_ssh_private_keys :: proc() -> (keys: [dynamic]string, ok: bool) {
	home, home_err := os.user_home_dir(context.allocator)
	if home_err != nil {
		fmt.eprintf("Error getting home dir: %v\n", home_err)
		return
	}

	ssh_dir, join_err := filepath.join([]string{home, ".ssh"})
	if join_err != nil {
		fmt.eprintf("Error building ssh path: %v\n", join_err)
		return
	}

	entries, dir_err := os.read_all_directory_by_path(ssh_dir, context.allocator)
	if dir_err != nil {
		fmt.eprintf("Could not read ~/.ssh directory: %v\n", dir_err)
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

find_git_roots :: proc(
	cfg: Config,
	allocator := context.temp_allocator,
) -> (
	roots: [dynamic]string,
	ok: bool,
) {
	paths := search_paths(cfg, allocator)
	// TODO: Pass allocator to findr
	findr.find_repos(paths[:], &roots, os.get_processor_core_count())
	ok = true
	return
}

search_paths :: proc(cfg: Config, allocator := context.allocator) -> [dynamic]string {
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil {
		panic("Failed to find home directory")
	}

	paths := new_clone(cfg.scan_config.include, allocator)

	for &include in paths {
		expanded, _ := strings.replace(include, "~", home, 1, allocator)
		if filepath.is_abs(expanded) {
			include = expanded
		} else {
			// TODO: show errors?
			resolved, err := filepath.abs(expanded, allocator)
			if err == nil {
				include = resolved
			}
		}
	}
	return paths^
}

envr_dir :: proc(config_path: string) -> string {
	return filepath.dir(config_path)
}

// User is responsible for freeing the path
data_path :: proc(
	config_path: string,
	allocator := context.allocator,
) -> (
	string,
	runtime.Allocator_Error,
) #optional_allocator_error {
	return filepath.join([]string{envr_dir(config_path), "data.envr"}, allocator)
}

