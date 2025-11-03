/*
Copyright © 2025 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"fmt"
	"strings"

	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

// restoreCmd represents the restore command
var restoreCmd = &cobra.Command{
	Use:   "restore",
	Short: "Install a .env file from the database into your file system",
	// Long:  ``,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		path := args[0]
		if len(strings.TrimSpace(path)) == 0 {
			return fmt.Errorf("No path provided")
		}

		db, err := app.Open()
		if err != nil {
			return err
		} else {
			defer db.Close(app.ReadOnly)
			record, err := db.Fetch(path)

			if err != nil {
				return err
			} else {
				err := record.Restore()

				if err != nil {
					return err
				} else {
					return nil
				}
			}
		}
	},
}

func init() {
	rootCmd.AddCommand(restoreCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// restoreCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// restoreCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
