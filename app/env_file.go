package app

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
)

type EnvFile struct {
	// TODO: Should use FileName in the struct and derive from the path.
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
	// The filesystem contents matches the struct
	// no further action is required.
	Noop EnvFileSyncResult = 0
	// The directory changed, but the file contents matched.
	// The database must be updated.
	DirUpdated EnvFileSyncResult = 1
	// The filesystem has been restored to match the struct
	// no further action is required.
	Restored EnvFileSyncResult = 1 << 1
	// The filesystem has been restored to match the struct.
	// The directory changed, so the database must be updated
	RestoredAndDirUpdated EnvFileSyncResult = Restored | DirUpdated
	// The struct has been updated from the filesystem
	// and should be updated in the database.
	BackedUp EnvFileSyncResult = 1 << 2
	Error    EnvFileSyncResult = 1 << 3
)

// Determines the source of truth when calling [EnvFile.Sync] or [EnvFile.Restore]
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
// dir to determine which side to use a the source of truth.
func (f *EnvFile) sync(dir syncDirection, db *Db) (result EnvFileSyncResult, err error) {
	if result != Noop {
		panic("Invalid state")
	}

	if _, err := os.Stat(f.Dir); err != nil {
		// Directory doesn't exist

		var movedDirs []string

		if db != nil {
			movedDirs, err = db.findMovedDirs(f)
		}
		if err != nil {
			return Error, err
		} else {
			switch len(movedDirs) {
			case 0:
				return Error, fmt.Errorf("directory missing")
			case 1:
				f.updateDir(movedDirs[0])
				result |= DirUpdated
			default:
				return Error, fmt.Errorf("multiple directories found")
			}
		}
	}

	if _, err := os.Stat(f.Path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			if err := os.WriteFile(f.Path, []byte(f.contents), 0644); err != nil {
				return Error, fmt.Errorf("failed to write file: %w", err)
			}

			return result | Restored, nil
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
			// No op, or DirUpdated
			return result, nil
		} else {
			switch dir {
			case TrustDatabase:
				if err := os.WriteFile(f.Path, []byte(f.contents), 0644); err != nil {
					return Error, fmt.Errorf("failed to write file: %w", err)
				}

				return result | Restored, nil
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

func (f *EnvFile) sharesRemote(remotes []string) bool {
	rMap := make(map[string]bool)
	for _, remote := range f.Remotes {
		rMap[remote] = true
	}

	for _, remote := range remotes {
		if rMap[remote] {
			return true
		}
	}

	return false
}

func (f *EnvFile) updateDir(newDir string) {
	f.Dir = newDir
	f.Path = path.Join(newDir, path.Base(f.Path))
	f.Remotes = getGitRemotes(newDir)
}

// Try to reconcile the EnvFile with the filesystem.
//
// If Updated is returned, [Db.Insert] should be called on file.
func (file *EnvFile) Sync() (result EnvFileSyncResult, err error) {
	return file.sync(TrustFilesystem, nil)
}

// Install the file into the file system. If the file already exists,
// it will be overwritten.
func (file EnvFile) Restore() error {
	_, err := file.sync(TrustDatabase, nil)

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
