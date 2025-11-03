package cmd

import (
	"fmt"

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
			defer db.Close(app.Write)
			files, err := db.List()

			if err != nil {
				return err
			} else {
				for _, file := range files {
					fmt.Printf("%s\n", file.Path)

					// Syncronize the filesystem with the database.
					changed, err := file.Sync()

					switch changed {
					case app.Updated:
						fmt.Printf("File updated - changes saved\n")
						if err := db.Insert(file); err != nil {
							return err
						}
					case app.Restored:
						fmt.Printf("File missing - restored backup\n")
					case app.Error:
						if err == nil {
							panic("err cannot be nil when Sync returns Error")
						} else {
							fmt.Printf("%s\n", err)
						}
					case app.Noop:
						fmt.Println("Nothing to do")
					default:
						panic("Unknown result")
					}

					fmt.Println("")
				}

				return nil
			}
		}
	},
}

func init() {
	rootCmd.AddCommand(syncCmd)
}
