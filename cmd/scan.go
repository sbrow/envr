package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/AlecAivazis/survey/v2"
	"github.com/mattn/go-isatty"
	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

var scanCmd = &cobra.Command{
	Use:   "scan",
	Short: "Find and select .env files for backup",
	RunE: func(cmd *cobra.Command, args []string) error {
		db, err := app.Open()
		if err != nil {
			return err
		}

		if db == nil {
			return fmt.Errorf("No db was loaded")
		}

		if err := db.CanScan(); err != nil {
			return err
		}

		files, err := db.Scan()
		if err != nil {
			return err
		}

		if len(files) == 0 {
			return fmt.Errorf("No .env files found to add.")
		}

		if isatty.IsTerminal(os.Stdout.Fd()) {
			selectedFiles, err := selectEnvFiles(files)
			if err != nil {
				return err
			}

			// Insert selected files into database
			var addedCount int
			for _, file := range selectedFiles {
				envFile := app.NewEnvFile(file)
				err := db.Insert(envFile)
				if err != nil {
					fmt.Printf("Error adding %s: %v\n", file, err)
				} else {
					addedCount++
				}
			}

			// Close database with write mode to persist changes
			if addedCount > 0 {
				err = db.Close(app.Write)
				if err != nil {
					return fmt.Errorf("Error saving changes: %v\n", err)
				} else {
					fmt.Printf("Successfully added %d file(s) to backup.\n", addedCount)
					return nil
				}
			} else {
				err = db.Close(app.ReadOnly)
				if err != nil {
					return fmt.Errorf("Error closing database: %v\n", err)
				}
				fmt.Println("No files were added.")
				return nil
			}
		} else {
			output, err := json.Marshal(files)
			if err != nil {
				return fmt.Errorf("Error marshaling files to JSON: %v", err)
			}
			fmt.Println(string(output))
			return nil
		}
	},
}

func init() {
	rootCmd.AddCommand(scanCmd)
}

func selectEnvFiles(files []string) ([]string, error) {
	var selectedFiles []string

	prompt := &survey.MultiSelect{
		Message: "Select .env files to backup:",
		Options: files,
	}

	err := survey.AskOne(prompt, &selectedFiles)
	if err != nil {
		return nil, err
	}

	return selectedFiles, nil
}
