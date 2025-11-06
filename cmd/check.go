package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/sbrow/envr/app"
	"github.com/spf13/cobra"
)

var checkCmd = &cobra.Command{
	Use:   "check [path]",
	Short: "check if files in the current directory are backed up",
	// TODO: Long description for new check command
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		// Accept an optional path arg, default to current working directory
		var checkPath string
		if len(args) > 0 {
			checkPath = args[0]
		} else {
			cwd, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("failed to get current working directory: %w", err)
			}
			checkPath = cwd
		}

		// Get absolute path
		absPath, err := filepath.Abs(checkPath)
		if err != nil {
			return fmt.Errorf("failed to get absolute path: %w", err)
		}

		// Open database
		db, err := app.Open()
		if err != nil {
			return fmt.Errorf("failed to open database: %w", err)
		}
		defer db.Close(app.ReadOnly)

		// Check if the path is a file or directory
		info, err := os.Stat(absPath)
		if err != nil {
			return fmt.Errorf("failed to stat path: %w", err)
		}

		var filesInPath []string

		if info.IsDir() {
			// Find .env files in the specified directory
			if err := db.CanScan(); err != nil {
				return err
			}

			// Scan only the specified path for .env files
			filesInPath, err = db.Scan([]string{absPath})
			if err != nil {
				return fmt.Errorf("failed to scan path for env files: %w", err)
			}
		} else {
			// Path is a file, just check this specific file
			filesInPath = []string{absPath}
		}

		// Get all backed up files from the database
		envFiles, err := db.List()
		if err != nil {
			return fmt.Errorf("failed to list files from database: %w", err)
		}

		// Check which files are not backed up
		var notBackedUp []string
		for _, file := range filesInPath {
			isBackedUp := false
			for _, envFile := range envFiles {
				if envFile.Path == file {
					isBackedUp = true
					break
				}
			}
			if !isBackedUp {
				notBackedUp = append(notBackedUp, file)
			}
		}

		// Display results
		if len(notBackedUp) == 0 {
			if len(filesInPath) == 0 {
				fmt.Println("No .env files found in the specified directory.")
			} else {
				fmt.Println("✓ All .env files in the directory are backed up.")
			}
		} else {
			fmt.Printf("Found %d .env file(s) that are not backed up:\n", len(notBackedUp))
			for _, file := range notBackedUp {
				fmt.Printf("  %s\n", file)
			}
			fmt.Println("\nRun 'envr sync' to back up these files.")
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(checkCmd)
}
