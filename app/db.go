package app

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"

	"filippo.io/age"
	_ "modernc.org/sqlite"
)

// CloseMode determines whether or not the in-memory DB should be saved to disk
// before closing the connection.
type CloseMode int

const (
	ReadOnly CloseMode = iota
	Write
)

type Db struct {
	db       *sql.DB
	cfg      Config
	features *AvailableFeatures
}

func Open() (*Db, error) {
	cfg, err := LoadConfig()
	if err != nil {
		return nil, err
	}

	if _, err := os.Stat("/home/spencer/.envr/data.age"); err != nil {
		// Create a new DB
		db, err := newDb()
		return &Db{db, *cfg, nil}, err
	} else {
		// Open the existing DB
		tmpFile, err := os.CreateTemp("", "envr-*.db")
		if err != nil {
			return nil, fmt.Errorf("failed to create temp file: %w", err)
		}
		defer tmpFile.Close()
		defer os.Remove(tmpFile.Name())

		err = decryptDb(tmpFile.Name(), (*cfg).Keys)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt database: %w", err)
		}

		memDb, err := newDb()
		if err != nil {
			return nil, fmt.Errorf("failed to open temp database: %w", err)
		}

		restoreDB(tmpFile.Name(), memDb)

		return &Db{memDb, *cfg, nil}, nil
	}
}

// Creates the database for the first time
func newDb() (*sql.DB, error) {
	db, err := sql.Open("sqlite", ":memory:")

	if err != nil {
		return nil, err
	} else {
		_, err := db.Exec(`create table envr_env_files (
      path text primary key not null
    , dir text not null
    , remotes text -- JSON
    , sha256 text not null
    , contents text not null
  );`)
		if err != nil {
			return nil, err
		} else {
			return db, err
		}
	}
}

// Decrypt the database from the age file into a temp sqlite file.
func decryptDb(tmpFilePath string, keys []SshKeyPair) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get user home directory: %w", err)
	}

	tmpFile, err := os.OpenFile(tmpFilePath, os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("failed to open temp file: %w", err)
	}
	defer tmpFile.Close()

	ageFilePath := filepath.Join(homeDir, ".envr", "data.age")
	ageFile, err := os.Open(ageFilePath)
	if err != nil {
		return fmt.Errorf("failed to open age file: %w", err)
	}
	defer ageFile.Close()

	identities := make([]age.Identity, 0, len(keys))

	for _, key := range keys {
		id, err := key.Identity()

		if err != nil {
			return err
		}

		identities = append(identities, id)
	}

	reader, err := age.Decrypt(ageFile, identities[:]...)
	if err != nil {
		return fmt.Errorf("failed to decrypt age file: %w", err)
	}

	_, err = io.Copy(tmpFile, reader)
	if err != nil {
		return fmt.Errorf("failed to copy decrypted content: %w", err)
	}

	return nil
}

// Restore the database from a file into memory
func restoreDB(path string, destDB *sql.DB) error {
	// Attach the source database
	_, err := destDB.Exec("ATTACH DATABASE ? AS source", path)
	if err != nil {
		return fmt.Errorf("failed to attach database: %w", err)
	}
	defer destDB.Exec("DETACH DATABASE source")

	// Copy data from source to destination
	_, err = destDB.Exec("INSERT INTO main.envr_env_files SELECT * FROM source.envr_env_files")
	if err != nil {
		return fmt.Errorf("failed to copy data: %w", err)
	}

	return nil
}

// Returns all the EnvFiles present in the database.
func (db *Db) List() (results []EnvFile, err error) {
	rows, err := db.db.Query("select * from envr_env_files")

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var envFile EnvFile
	var remotesJson []byte
	for rows.Next() {
		err := rows.Scan(&envFile.Path, &envFile.Dir, &remotesJson, &envFile.Sha256, &envFile.contents)
		if err != nil {
			return nil, err
		}

		if err := json.Unmarshal(remotesJson, &envFile.Remotes); err != nil {
			return nil, err
		}

		results = append(results, envFile)
	}

	if err = rows.Err(); err != nil {
		return nil, err
	}

	return results, nil
}

func (db *Db) Close(mode CloseMode) error {
	defer db.db.Close()

	if mode == Write {
		// Create tmp file
		tmpFile, err := os.CreateTemp("", "envr-*.db")
		if err != nil {
			return fmt.Errorf("failed to create temp file: %w", err)
		}
		defer tmpFile.Close()
		defer os.Remove(tmpFile.Name())

		if err := backupDb(db.db, tmpFile.Name()); err != nil {
			return err
		}

		if err := encryptDb(tmpFile.Name(), db.cfg.Keys); err != nil {
			return err
		}
	}

	return nil
}

// Save the in-memory database to a tmp file.
func backupDb(memDb *sql.DB, tmpFilePath string) error {
	_, err := memDb.Exec("VACUUM INTO ?", tmpFilePath)
	if err != nil {
		return fmt.Errorf("failed to vacuum database to file: %w", err)
	}

	return nil
}

// Encrypt the database from the temp sqlite file into an age file.
func encryptDb(tmpFilePath string, keys []SshKeyPair) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get user home directory: %w", err)
	}
	ageFilePath := filepath.Join(homeDir, ".envr", "data.age")

	// Ensure .envr directory exists
	err = os.MkdirAll(filepath.Dir(ageFilePath), 0755)
	if err != nil {
		return fmt.Errorf("failed to create .envr directory: %w", err)
	}

	// Open temp file for reading
	tmpFile, err := os.Open(tmpFilePath)
	if err != nil {
		return fmt.Errorf("failed to open temp file: %w", err)
	}
	defer tmpFile.Close()

	// Open/create age file for writing (this preserves hardlinks)
	ageFile, err := os.OpenFile(ageFilePath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return fmt.Errorf("failed to open age file: %w", err)
	}
	defer ageFile.Close()

	recipients := make([]age.Recipient, 0, len(keys))
	for _, key := range keys {
		recipient, err := key.Recipient()

		if err != nil {
			return err
		}

		recipients = append(recipients, recipient)
	}

	writer, err := age.Encrypt(ageFile, recipients...)
	if err != nil {
		return fmt.Errorf("failed to create age writer: %w", err)
	}

	_, err = io.Copy(writer, tmpFile)
	if err != nil {
		return fmt.Errorf("failed to encrypt and write data: %w", err)
	}

	err = writer.Close()
	if err != nil {
		return fmt.Errorf("failed to close age writer: %w", err)
	}

	return nil
}

func (db *Db) Insert(file EnvFile) error {
	// Marshal remotes to JSON
	remotesJSON, err := json.Marshal(file.Remotes)
	if err != nil {
		return fmt.Errorf("failed to marshal remotes: %w", err)
	}

	// Insert into database
	_, err = db.db.Exec(`
		INSERT OR REPLACE INTO envr_env_files (path, dir, remotes, sha256, contents)
		VALUES (?, ?, ?, ?, ?)
	`, file.Path, file.Dir, string(remotesJSON), file.Sha256, file.contents)

	if err != nil {
		return fmt.Errorf("failed to insert env file: %w", err)
	}

	return nil
}

// Select a single EnvFile from the database.
func (db *Db) Fetch(path string) (envFile EnvFile, err error) {
	var remotesJSON string

	row := db.db.QueryRow("SELECT path, dir, remotes, sha256, contents FROM envr_env_files WHERE path = ?", path)
	err = row.Scan(&envFile.Path, &envFile.Dir, &remotesJSON, &envFile.Sha256, &envFile.contents)
	if err != nil {
		return EnvFile{}, fmt.Errorf("failed to fetch env file: %w", err)
	}

	if err = json.Unmarshal([]byte(remotesJSON), &envFile.Remotes); err != nil {
		return EnvFile{}, fmt.Errorf("failed to unmarshal remotes: %w", err)
	}

	return envFile, nil
}

// Removes a file from the database, if present.
func (db *Db) Delete(path string) error {
	result, err := db.db.Exec("DELETE FROM envr_env_files WHERE path = ?", path)
	if err != nil {
		return fmt.Errorf("failed to delete env file: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("no file found with path: %s", path)
	}

	return nil
}

// Finds .env files in the filesystem that aren't present in the database.
// path overrides the already configured
func (db *Db) Scan(paths []string) ([]string, error) {
	cfg := db.cfg

	if paths != nil {
		cfg.ScanConfig.Include = paths
	}

	all_paths, err := cfg.scan()
	if err != nil {
		return []string{}, err
	}

	untracked_paths := make([]string, 0, len(all_paths)/2)
	env_files, err := db.List()

	if err != nil {
		return untracked_paths, err
	}

	for _, path := range all_paths {
		backed_up := slices.ContainsFunc(env_files, func(e EnvFile) bool {
			return e.Path == path
		})

		if backed_up {
			continue
		} else {
			untracked_paths = append(untracked_paths, path)
		}
	}

	return untracked_paths, nil
}

// Determine the available features on the installed system.
func (db *Db) Features() AvailableFeatures {
	if db.features == nil {
		feats := checkFeatures()
		db.features = &feats
	}

	return *db.features
}

// Returns nil if [Db.Scan] is safe to use, null otherwise.
func (db *Db) CanScan() error {
	if db.Features()&Fd == 0 {
		return fmt.Errorf(
			"please install fd to use the scan function (https://github.com/sharkdp/fd)",
		)
	} else {
		return nil
	}
}
