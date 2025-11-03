package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "envr",
	Short: "Manage your .env files.",
	Long: `envr keeps your .env synced to a local, age encrypted database.
Is a safe and eay way to gather all your .env files in one place where they can
easily be backed by another tool such as restic or git.

All your data is stored in ~/data.age

Getting started is easy:

1. Create your configuration file and set up encrypted storage:

> envr init

2. Scan for existing .env files:

> envr scan

Select the files you want to back up from the interactive list.

3. Verify that it worked:

> envr list

4. After changing any of your .env files, update the backup with:

> envr sync

5. If you lose a repository, after re-cloning the repo into the same path it was
at before, restore your backup with:

> envr restore ~/&lt;path to repository&gt;/.env`,
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	// rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.envr.yaml)")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	// rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}

// Expose the root command for our generators.
func Root() *cobra.Command { return rootCmd }
