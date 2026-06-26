package main

import "core:fmt"
import "core:terminal/ansi"

cmd_init :: proc(cmd: ^Command) {
	force := cmd.flags.force
	config_file := cmd.flags.config_file

	fmt.wprintln(cmd.out, cmd.flags.config_file, flush = false)

	_, cfg_exists := load_config(config_file)
	if cfg_exists && !force {
		fmt.wprintln(
			cmd.out,
			`You have already initialized envr.
Run again with the --force flag if you want to reinitialize.`,
			flush = false,
		)
		return
	}

	keys, ok := find_ssh_private_keys()
	if !ok {
		return
	}

	if len(keys) == 0 {
		fmt.wprintln(
			cmd.err,
			`No ssh-ed25519 keys found in ~/.ssh
Generate one with: ssh-keygen -t ed25519`,
			flush = false,
		)
		return
	}

	selected, result := multi_select("Select SSH private keys:", keys[:])
	defer delete(selected)
	if result == .Cancel {
		fmt.wprintln(
			cmd.out,
			ansi.CSI + ansi.FAINT + ansi.SGR + "Cancelled." + ANSI_RESET,
			flush = false,
		)
		return
	}

	selected_paths := make([dynamic]string, 0, min(1, len(keys) / 2))
	for i in 0 ..< len(keys) {
		if selected[i] {
			append(&selected_paths, keys[i])
		}
	}

	if len(selected_paths) == 0 {
		fmt.wprintln(cmd.err, "No SSH keys selected - Config not created", flush = false)
		return
	}

	cfg := new_config(selected_paths[:], config_file)
	if !save_config(cfg, force = force) {
		return
	}

	fmt.wprintf(
		cmd.out,
		"Config initialized with %d SSH key(s). You are ready to use envr.\n",
		len(selected_paths),
		flush = false,
	)
}

