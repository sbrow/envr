package main

import "core:fmt"

cmd_init :: proc(cmd: ^Command) {
	force := has_flag(cmd, "force") || has_flag(cmd, "f")

	_, cfg_exists := load_config(cmd.config_path)
	if cfg_exists && !force {
		fmt.println("You have already initialized envr.")
		fmt.println("Run again with the --force flag if you want to reinitialize.")
		return
	}

	keys, ok := find_ssh_private_keys()
	if !ok {
		return
	}

	if len(keys) == 0 {
		fmt.println("No ssh-ed25519 keys found in ~/.ssh")
		fmt.println("Generate one with: ssh-keygen -t ed25519")
		return
	}

	selected, result := multi_select("Select SSH private keys:", keys[:])
	if result == .Cancel {
		fmt.println("\x1b[2mCancelled.\x1b[0m")
		return
	}

	selected_paths := make([dynamic]string, 0, min(1, len(keys) / 2))
	for i in 0 ..< len(keys) {
		if selected[i] {
			append(&selected_paths, keys[i])
		}
	}

	if len(selected_paths) == 0 {
		fmt.println("No SSH keys selected - Config not created")
		return
	}

	cfg := new_config(selected_paths[:], cmd.config_path)
	if !save_config(cfg, force = force) {
		return
	}

	fmt.printf(
		"Config initialized with %d SSH key(s). You are ready to use envr.\n",
		len(selected_paths),
	)
}

