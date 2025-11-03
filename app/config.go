package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"filippo.io/age"
	"filippo.io/age/agessh"
)

type Config struct {
	Keys       []SshKeyPair `json:"keys"`
	ScanConfig scanConfig   `json:"scan"`
}

type SshKeyPair struct {
	Private string `json:"private"` // Path to the private key file
	Public  string `json:"public"`  // Path to the public key file
}

type scanConfig struct {
	Matcher string `json:"matcher"`
	Exclude string `json:"exclude"`
	Include string `json:"include"`
}

// Create a fresh config with sensible defaults.
func NewConfig(privateKeyPaths []string) Config {
	var keys = []SshKeyPair{}

	for _, priv := range privateKeyPaths {
		var key = SshKeyPair{
			Private: priv,
			Public:  priv + ".pub",
		}

		keys = append(keys, key)
	}

	return Config{
		Keys: keys,
		ScanConfig: scanConfig{
			Matcher: "\\.env",
			Exclude: "*.envrc",
			Include: "~",
		},
	}
}

// Read the Config from disk.
func LoadConfig() (*Config, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	configPath := filepath.Join(homeDir, ".envr", "config.json")

	data, err := os.ReadFile(configPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("No config file found. Please run `envr init` to generate one.")
		} else {
			return nil, err
		}
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}

	return &config, nil
}

// Write the Config to disk.
func (c *Config) Save() error {
	// Create the ~/.envr directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	configDir := filepath.Join(homeDir, ".envr")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return err
	}

	configPath := filepath.Join(configDir, "config.json")

	// Check if file exists and is not empty
	if info, err := os.Stat(configPath); err == nil {
		if info.Size() > 0 {
			return os.ErrExist
		}
	}

	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0644)
}

// Use fd to find all ignored .env files that match the config's parameters
func (c Config) scan() (paths []string, err error) {
	searchPath, err := c.searchPath()
	if err != nil {
		return []string{}, err
	}

	// Find all files (including ignored ones)
	fmt.Printf("Searching for all files in \"%s\"...\n", searchPath)
	allCmd := exec.Command("fd", "-a", c.ScanConfig.Matcher, "-E", c.ScanConfig.Exclude, "-HI", searchPath)
	allOutput, err := allCmd.Output()
	if err != nil {
		return []string{}, err
	}

	allFiles := strings.Split(strings.TrimSpace(string(allOutput)), "\n")
	if len(allFiles) == 1 && allFiles[0] == "" {
		allFiles = []string{}
	}

	// Find unignored files
	fmt.Printf("Search for unignored fies in \"%s\"...\n", searchPath)
	unignoredCmd := exec.Command("fd", "-a", c.ScanConfig.Matcher, "-E", c.ScanConfig.Exclude, "-H", searchPath)
	unignoredOutput, err := unignoredCmd.Output()
	if err != nil {
		return []string{}, err
	}

	unignoredFiles := strings.Split(strings.TrimSpace(string(unignoredOutput)), "\n")
	if len(unignoredFiles) == 1 && unignoredFiles[0] == "" {
		unignoredFiles = []string{}
	}

	// Create a map for faster lookup
	unignoredMap := make(map[string]bool)
	for _, file := range unignoredFiles {
		unignoredMap[file] = true
	}

	// Filter to get only ignored files
	var ignoredFiles []string
	for _, file := range allFiles {
		if !unignoredMap[file] {
			ignoredFiles = append(ignoredFiles, file)
		}
	}

	return ignoredFiles, nil
}

func (c Config) searchPath() (path string, err error) {
	include := c.ScanConfig.Include

	if include == "~" {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return homeDir, nil
	}

	absPath, err := filepath.Abs(include)
	if err != nil {
		return "", err
	}

	return absPath, nil
}

// TODO: Should this be private?
func (s SshKeyPair) Identity() (age.Identity, error) {
	sshKey, err := os.ReadFile(s.Private)
	if err != nil {
		return nil, fmt.Errorf("failed to read SSH key: %w", err)
	}

	id, err := agessh.ParseIdentity(sshKey)
	if err != nil {
		return nil, fmt.Errorf("failed to parse SSH identity: %w", err)
	}

	return id, nil
}

// TODO: Should this be private?
func (s SshKeyPair) Recipient() (age.Recipient, error) {
	sshKey, err := os.ReadFile(s.Public)
	if err != nil {
		return nil, fmt.Errorf("failed to read SSH key: %w", err)
	}

	id, err := agessh.ParseRecipient(string(sshKey))
	if err != nil {
		return nil, fmt.Errorf("failed to parse SSH identity: %w", err)
	}

	return id, nil
}
