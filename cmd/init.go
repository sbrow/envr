package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/AlecAivazis/survey/v2"
	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

// TODO: Add --force (-f) flag.
var initCmd = &cobra.Command{
	Use:                   "init",
	DisableFlagsInUseLine: true,
	Short:                 "Set up envr",
	Long: `The init command generates your initial config and saves it to
~/.envr/config in JSON format.

During setup, you will be prompted to select one or more ssh keys with which to
encrypt your databse. **Make 100% sure** that you have **a remote copy** of this
key somewhere, otherwise your data could be lost forever.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		config, _ := app.LoadConfig()

		if config != nil {
			return fmt.Errorf("You have already initialized envr")
		} else {
			keys, err := selectSSHKeys()
			if err != nil {
				return fmt.Errorf("Error selecting SSH keys: %v", err)
			}

			if len(keys) == 0 {
				return fmt.Errorf("No SSH keys selected - Config not created")
			}

			cfg := app.NewConfig(keys)
			if err := cfg.Save(); err != nil {
				return err
			}

			fmt.Printf("Config initialized with %d SSH key(s). You are ready to use envr.\n", len(keys))
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(initCmd)
}

func selectSSHKeys() ([]string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	// TODO: Support reading from ssh-agent
	sshDir := filepath.Join(homeDir, ".ssh")
	entries, err := os.ReadDir(sshDir)
	if err != nil {
		return nil, fmt.Errorf("could not read ~/.ssh directory: %w", err)
	}

	var privateKeys []string
	for _, entry := range entries {
		name := entry.Name()
		if !entry.IsDir() && !strings.HasSuffix(name, ".pub") &&
			!strings.Contains(name, "known_hosts") && !strings.Contains(name, "config") {
			privateKeys = append(privateKeys, filepath.Join(sshDir, name))
		}
	}

	if len(privateKeys) == 0 {
		return nil, fmt.Errorf("no SSH private keys found in ~/.ssh")
	}

	var selected []string

	prompt := &survey.MultiSelect{
		Message: "Select SSH private keys:",
		Options: privateKeys,
	}

	err = survey.AskOne(prompt, &selected)
	if err != nil {
		return nil, err
	}

	return selected, nil
}
