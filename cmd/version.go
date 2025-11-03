package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

var long bool

// versionCmd represents the version command
var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show envr's version",
	Run: func(cmd *cobra.Command, args []string) {
		if long {
			fmt.Printf("envr version %s\n", version)
			fmt.Printf("commit: %s\n", commit)
			fmt.Printf("built: %s\n", date)
		} else {
			fmt.Printf("%s\n", version)
		}
	},
}

func init() {
	versionCmd.Flags().BoolVarP(&long, "long", "l", false, "Show all version information")
	rootCmd.AddCommand(versionCmd)
}
