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

// backupCmd represents the backup command
var backupCmd = &cobra.Command{
	Use:   "backup <path>",
	Short: "Import a .env file into envr",
	Args:  cobra.ExactArgs(1),
	// Long: `Long desc`
	RunE: func(cmd *cobra.Command, args []string) error {
		path := args[0]
		if len(strings.TrimSpace(path)) == 0 {
			return fmt.Errorf("No path provided")
		}

		db, err := app.Open()
		if err != nil {
			return err
		} else {
			defer db.Close()
			record := app.NewEnvFile(path)

			if err := db.Insert(record); err != nil {
				panic(err)
			} else {
				fmt.Printf("Saved %s into the database", path)
				return nil
			}
		}
	},
}

func init() {
	rootCmd.AddCommand(backupCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// backupCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// backupCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
