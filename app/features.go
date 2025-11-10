package app

import (
	"fmt"
	"os/exec"
)

type MissingFeatureError struct {
	feature AvailableFeatures
}

func (m *MissingFeatureError) Error() string {
	return fmt.Sprintf("Missing \"%s\" feature", m.feature)
}

// TODO: Features should really be renamed to Binaries

// Represents which binaries are present in $PATH.
// Used to fail safely when required features are unavailable
type AvailableFeatures int

const (
	Git AvailableFeatures = 1
	// fd
	Fd AvailableFeatures = 2
	// All features are present
	All AvailableFeatures = Git | Fd
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

// Returns a MissingFeature error if the given features aren't present.
func (a AvailableFeatures) validateFeatures(features ...AvailableFeatures) error {
	var missing AvailableFeatures

	for _, feat := range features {
		if a&feat == 0 {
			missing |= feat
		}
	}

	if missing == 0 {
		return nil
	} else {
		return &MissingFeatureError{missing}
	}
}
