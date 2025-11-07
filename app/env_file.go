package app

import (
	"crypto/sha256"
	"errors"
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
	BackedUp EnvFileSyncResult = iota
	// The filesystem has been restored to match the struct
	// no further action is required.
	Restored
	Error
	// The filesystem contents matches the struct
	// no further action is required.
	Noop
)

type syncDirection int

const (
	TrustDatabase syncDirection = iota
	TrustFilesystem
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

// Reconcile the state of the database with the state of the filesystem, using
// dir to determine which side to use a the source of truth
func (f *EnvFile) sync(dir syncDirection) (result EnvFileSyncResult, err error) {
	// How Sync should work
	//
	// If the directory doesn't exist, look for other directories with the same remote(s)
	// -> If one is found, update file.Dir and File.Path, then continue with "changed" flag
	// -> If multiple are found, return an error
	// -> If none are found, return a different error

	// Ensure the directory exists
	if _, err := os.Stat(f.Dir); err != nil {
		return Error, fmt.Errorf("directory missing")
	}

	if _, err := os.Stat(f.Path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			if err := os.WriteFile(f.Path, []byte(f.contents), 0644); err != nil {
				return Error, fmt.Errorf("failed to write file: %w", err)
			}

			return Restored, err
		} else {
			return Error, err
		}
	} else {
		// File exists, check its hash
		contents, err := os.ReadFile(f.Path)
		if err != nil {
			return Error, fmt.Errorf("failed to read file for SHA comparison: %w", err)
		}

		hash := sha256.Sum256(contents)
		currentSha := fmt.Sprintf("%x", hash)

		// Compare the hashes
		if currentSha == f.Sha256 {
			return Noop, nil
		} else {
			switch dir {
			case TrustDatabase:
				if err := os.WriteFile(f.Path, []byte(f.contents), 0644); err != nil {
					return Error, fmt.Errorf("failed to write file: %w", err)
				}
				return Restored, nil
			case TrustFilesystem:
				// Overwrite the database
				if err = f.Backup(); err != nil {
					return Error, err
				} else {
					return BackedUp, nil
				}
			default:
				panic("unknown sync direction")
			}
		}
	}
}

// Try to reconcile the EnvFile with the filesystem.
//
// If Updated is returned, [Db.Insert] should be called on file.
func (file *EnvFile) Sync() (result EnvFileSyncResult, err error) {
	return file.sync(TrustFilesystem)
}

// Install the file into the file system. If the file already exists,
// it will be overwritten.
func (file EnvFile) Restore() error {
	_, err := file.sync(TrustDatabase)

	return err
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
