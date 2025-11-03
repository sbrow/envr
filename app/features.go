package app

import (
	"os/exec"
)

// Represents which binaries are present in $PATH.
// Used to fail safely when required features are unavailable
type AvailableFeatures int

const (
	Git AvailableFeatures = 1
	// fd
	Fd AvailableFeatures = 2
	// All features are present
	All AvailableFeatures = Git & Fd
)

// Checks for available features.
func checkFeatures() (feats AvailableFeatures) {
	// Check for git binary
	if _, err := exec.LookPath("git"); err == nil {
		feats |= Git
	}

	// Check for fd binary
	if _, err := exec.LookPath("fd"); err == nil {
		feats |= Fd
	}

	return feats
}
