package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/mattn/go-isatty"
	"github.com/olekukonko/tablewriter"
	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

type listEntry struct {
	Directory string `json:"directory"`
	Path      string `json:"path"`
}

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "View your tracked files",
	RunE: func(cmd *cobra.Command, args []string) error {
		db, err := app.Open()
		if err != nil {
			return err
		}
		defer db.Close(app.ReadOnly)

		rows, err := db.List()
		if err != nil {
			return err
		}

		if isatty.IsTerminal(os.Stdout.Fd()) {
			table := tablewriter.NewWriter(os.Stdout)
			table.Header([]string{"Directory", "Path"})

			for _, row := range rows {
				path, err := filepath.Rel(row.Dir, row.Path)
				if err != nil {
					return err
				}
				table.Append([]string{row.Dir + "/", path})
			}
			table.Render()
		} else {
			var entries []listEntry
			for _, row := range rows {
				path, err := filepath.Rel(row.Dir, row.Path)
				if err != nil {
					return err
				}
				entries = append(entries, listEntry{
					Directory: row.Dir + "/",
					Path:      path,
				})
			}

			encoder := json.NewEncoder(os.Stdout)
			return encoder.Encode(entries)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
}
