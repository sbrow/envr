package cmd

import (
	"os"

	"github.com/olekukonko/tablewriter"
	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

var depsCmd = &cobra.Command{
	Use:   "deps",
	Short: "Check for missing binaries",
	Long: `envr relies on external binaries for certain functionality.

The check command reports on which binaries are available and which are not.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		db, err := app.Open()
		if err != nil {
			return err
		} else {
			defer db.Close(app.ReadOnly)
			features := db.Features()

			table := tablewriter.NewWriter(os.Stdout)
			table.Header([]string{"Feature", "Status"})

			// Check Git
			if features&app.Git == 1 {
				table.Append([]string{"Git", "✓ Available"})
			} else {
				table.Append([]string{"Git", "✗ Missing"})
			}

			// Check fd
			if features&app.Fd == app.Fd {
				table.Append([]string{"fd", "✓ Available"})
			} else {
				table.Append([]string{"fd", "✗ Missing"})
			}

			table.Render()

			return nil
		}
	},
}

func init() {
	rootCmd.AddCommand(depsCmd)
}
