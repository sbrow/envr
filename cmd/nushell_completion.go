package cmd

import (
	_ "embed"
	"fmt"

	"github.com/spf13/cobra"
)

//go:embed mod.nu
var completion string

// nushellCompletionCmd represents the nushellCompletion command
var nushellCompletionCmd = &cobra.Command{
	Use:   "nushell-completion",
	Short: "Generate custom completions for nushell",
	Long: `At time of writing, cobra does not natively support nushell,
so a custom command had to be written`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(completion)
	},
}

func init() {
	rootCmd.AddCommand(nushellCompletionCmd)
}
