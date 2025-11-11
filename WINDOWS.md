# Windows Compatibility Guide

This document outlines Windows compatibility issues and solutions for the envr project.

## Critical Issues

### 1. Path Handling Bug (MUST FIX)

**File:** `app/env_file.go:209`

**Issue:** Uses `path.Join` instead of `filepath.Join`, which won't work correctly on Windows due to different path separators.

**Current code:**
```go
f.Path = path.Join(newDir, path.Base(f.Path))
```

**Fixed code:**
```go
f.Path = filepath.Join(newDir, filepath.Base(f.Path))
```

## External Dependencies

The application relies on external tools that need to be installed separately on Windows:

### Required Tools

1. **fd** - Fast file finder
   - Install via: `winget install sharkdp.fd` or `choco install fd`
   - Alternative: `scoop install fd`

2. **git** - Version control system
   - Install via: `winget install Git.Git` or download from git-scm.com
   - Usually already available on most development machines

## Minor Compatibility Notes

### File Permissions
- Unix file permissions (`0755`, `0644`) are used throughout the codebase
- These are safely ignored on Windows - no changes needed

### Editor Configuration
**File:** `cmd/edit_config.go:20-24`

**Issue:** Relies on `$EDITOR` environment variable which is less common on Windows.

**Current behavior:** Fails if `$EDITOR` is not set

**Recommended improvement:** Add fallback detection for Windows editors:
```go
editor := os.Getenv("EDITOR")
if editor == "" {
    if runtime.GOOS == "windows" {
        editor = "notepad.exe"  // or "code.exe" for VS Code
    } else {
        fmt.Println("Error: $EDITOR environment variable is not set")
        return
    }
}
```

## Installation Instructions for Windows

1. Install required dependencies:
   ```powershell
   winget install sharkdp.fd
   winget install Git.Git
   ```

2. Fix the path handling bug in `app/env_file.go:209`

3. Build and run as normal:
   ```powershell
   go build
   .\envr.exe init
   ```

## Testing on Windows

After applying the critical path fix, the core functionality should work correctly on Windows. The application has been designed with cross-platform compatibility in mind, using:

- `filepath` package for path operations (mostly)
- `os.UserHomeDir()` for home directory detection
- Standard Go file operations

## Summary

- **1 critical bug** must be fixed for Windows compatibility
- **2 external tools** need to be installed
- **1 minor enhancement** recommended for better Windows UX
- Overall architecture is Windows-compatible
