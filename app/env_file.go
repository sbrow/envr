package app

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type EnvFile struct {
	Path string
	// Dir is derived from Path, and is not stored in the database.
	Dir      string
	Remotes  []string // []string
	Sha256   string
	contents string
}

// The result returned by [EnvFile.Sync]
type EnvFileSyncResult int

const (
	// The struct has been updated from the filesystem
	// and should be updated in the database.
	Updated EnvFileSyncResult = iota
	// The filesystem has been restored to match the struct
	// no further action is required.
	Restored
	Error
	// The filesystem contents matches the struct
	// no further action is required.
	Noop
)

func NewEnvFile(path string) EnvFile {
	// Get absolute path and directory
	absPath, err := filepath.Abs(path)
	if err != nil {
		panic(fmt.Errorf("failed to get absolute path: %w", err))
	}
	dir := filepath.Dir(absPath)

	// Get git remotes
	remotes := getGitRemotes(dir)

	// Read the file contents
	contents, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Errorf("failed to read file %s: %w", path, err))
	}

	// Calculate SHA256 hash
	hash := sha256.Sum256(contents)
	sha256Hash := fmt.Sprintf("%x", hash)

	return EnvFile{
		Path:     absPath,
		Dir:      dir,
		Remotes:  remotes,
		Sha256:   sha256Hash,
		contents: string(contents),
	}
}

func getGitRemotes(dir string) []string {
	// TODO: Check for Git flag and change behaviour if unset.
	cmd := exec.Command("git", "remote", "-v")
	cmd.Dir = dir

	output, err := cmd.Output()
	if err != nil {
		// Not a git repository or git command failed
		return []string{}
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	remoteSet := make(map[string]bool)

	for _, line := range lines {
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			remoteSet[parts[1]] = true
		}
	}

	remotes := make([]string, 0, len(remoteSet))
	for remote := range remoteSet {
		remotes = append(remotes, remote)
	}

	return remotes
}

// Try to reconcile the EnvFile with the filesystem.
//
// If Updated is returned, [Db.Insert] should be called on file.
func (file *EnvFile) Sync() (result EnvFileSyncResult, err error) {
	// TODO: If the directory doesn't exist, look for other directories with the same remote(s)
	// TODO: If one is found, update file.Dir and File.Path
	// TODO: If nothing if found, return an error
	// TODO: If more than one is found, return a different error

	// Check if the path exists in the file system
	_, err = os.Stat(file.Path)
	if err == nil {
		contents, err := os.ReadFile(file.Path)
		if err != nil {
			return Error, fmt.Errorf("failed to read file for SHA comparison: %w", err)
		}

		// Check if sha matches by reading the current file and calculating its hash
		hash := sha256.Sum256(contents)
		currentSha := fmt.Sprintf("%x", hash)
		if file.Sha256 == currentSha {
			// Nothing to do
			return Noop, nil
		} else {
			if err = file.Backup(); err != nil {
				return Error, err
			} else {
				return Updated, nil
			}
		}
	} else {
		if err = file.Restore(); err != nil {
			return Error, err
		} else {
			return Restored, nil
		}
	}
}

// Install the file into the file system. If the file already exists,
// it will be overwritten.
func (file EnvFile) Restore() error {
	// TODO: Duplicate work is being done when called from the Sync function.
	if _, err := os.Stat(file.Path); err == nil {
		// file already exists

		// Read existing file and calculate its hash
		existingContents, err := os.ReadFile(file.Path)
		if err != nil {
			return fmt.Errorf("failed to read existing file for hash comparison: %w", err)
		}

		hash := sha256.Sum256(existingContents)
		existingSha := fmt.Sprintf("%x", hash)

		if existingSha == file.Sha256 {
			return fmt.Errorf("file already exists: %s", file.Path)
		} else {
			if err := os.WriteFile(file.Path, []byte(file.contents), 0644); err != nil {
				return fmt.Errorf("failed to write file: %w", err)
			}

			return nil
		}
	} else {
		// file doesn't exist

		// Ensure the directory exists
		if _, err := os.Stat(file.Dir); err != nil {
			return fmt.Errorf("directory missing")
		}

		// Write the contents to the file
		if err := os.WriteFile(file.Path, []byte(file.contents), 0644); err != nil {
			return fmt.Errorf("failed to write file: %w", err)
		}

		return nil
	}
}

// Update the EnvFile using the file system.
func (file *EnvFile) Backup() error {
	// Read the contents of the file
	contents, err := os.ReadFile(file.Path)
	if err != nil {
		return fmt.Errorf("failed to read file %s: %w", file.Path, err)
	}

	// Update file.contents to match
	file.contents = string(contents)

	// Update file.sha256
	hash := sha256.Sum256(contents)
	file.Sha256 = fmt.Sprintf("%x", hash)

	return nil
}
