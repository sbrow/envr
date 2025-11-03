/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
)

var editConfigCmd = &cobra.Command{
	Use:   "edit-config",
	Short: "Edit your config with your default editor",
	// Long: ``,
	Run: func(cmd *cobra.Command, args []string) {
		editor := os.Getenv("EDITOR")
		if editor == "" {
			fmt.Println("Error: $EDITOR environment variable is not set")
			return
		}

		homeDir, err := os.UserHomeDir()
		if err != nil {
			fmt.Printf("Error getting home directory: %v\n", err)
			return
		}

		configPath := filepath.Join(homeDir, ".envr", "config.json")

		// Check if config file exists
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			fmt.Printf("Config file does not exist at %s. Run 'envr init' first.\n", configPath)
			return
		}

		// Execute the editor
		execCmd := exec.Command(editor, configPath)
		execCmd.Stdin = os.Stdin
		execCmd.Stdout = os.Stdout
		execCmd.Stderr = os.Stderr

		if err := execCmd.Run(); err != nil {
			fmt.Printf("Error running editor: %v\n", err)
			return
		}
	},
}

func init() {
	rootCmd.AddCommand(editConfigCmd)
}
