package cmd

import (
	"encoding/json"
	"os"

	"github.com/mattn/go-isatty"
	"github.com/olekukonko/tablewriter"
	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

// TODO: Detect when file paths have moved and update accordingly.
var syncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Update or restore your env backups",
	RunE: func(cmd *cobra.Command, args []string) error {
		db, err := app.Open()
		if err != nil {
			return err
		} else {
			defer db.Close()
			files, err := db.List()

			if err != nil {
				return err
			} else {
				type syncResult struct {
					Path   string `json:"path"`
					Status string `json:"status"`
				}
				var results []syncResult

				for _, file := range files {
					// Syncronize the filesystem with the database.
					changed, err := file.Sync()

					var status string
					switch changed {
					case app.Updated:
						status = "Backed Up"
						if err := db.Insert(file); err != nil {
							return err
						}
					case app.Restored:
						status = "Restored"
					case app.Error:
						if err == nil {
							panic("err cannot be nil when Sync returns Error")
						}
						status = err.Error()
					case app.Noop:
						status = "OK"
					default:
						panic("Unknown result")
					}

					results = append(results, syncResult{
						Path:   file.Path,
						Status: status,
					})
				}

				if isatty.IsTerminal(os.Stdout.Fd()) {
					table := tablewriter.NewWriter(os.Stdout)
					table.Header([]string{"File", "Status"})

					for _, result := range results {
						table.Append([]string{result.Path, result.Status})
					}
					table.Render()
				} else {
					encoder := json.NewEncoder(os.Stdout)
					return encoder.Encode(results)
				}

				return nil
			}
		}
	},
}

func init() {
	rootCmd.AddCommand(syncCmd)
}
