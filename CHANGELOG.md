# Changelog

## [0.3.0](https://github.com/sbrow/envr/compare/v0.2.1...v0.3.0) (2026-06-16)

Version 0.3.0 represents a significant departure (and improvement) for envr.
The entire codebase was rewritten in [Odin](https://odin-lang.org/) (from Go).
This reduced the binary size from over 17MB to under 600k, improved performance,
and significantly reduced the number of project dependencies from 69 to just 2.

### ⚠ BREAKING CHANGES

* The encryption format of databases has changed. Age encryption is no longer supported, and no automatic migration path was implemented.

### Features

* All encryption/decryption now happens in-memory. ([fe2b256](https://github.com/sbrow/envr/commit/fe2b256bd61eaf551d53faf3893b473a64a94667))
* Config can be loaded from any path with `--config-file (-c)` flag. ([4a26ee8](https://github.com/sbrow/envr/commit/4a26ee814591e6aab0eb99d2359d51b31011edfe))
* Switched from age to libsodium. ([23b8c2d](https://github.com/sbrow/envr/commit/23b8c2dc671a23cf76cf6746b33806ded9381486))


### Performance Improvements

* Improved writer performance. ([365e914](https://github.com/sbrow/envr/commit/365e9149b1a738ac9119bb5f74dc7e047ecfed5b))

## [0.2.1](https://github.com/sbrow/envr/compare/v0.2.0...v0.2.1) (2026-01-12)


### Bug Fixes

* Added `add` as an alias for backup. ([cf363ab](https://github.com/sbrow/envr/commit/cf363abc4d8cec208d23c6acedbb7e0dd6900332))

## [0.2.0](https://github.com/sbrow/envr/compare/v0.1.1...v0.2.0) (2025-11-10)


### ⚠ BREAKING CHANGES

* Dir is now derived from Path rather than stored in the DB. Your DB will need to be updated.
* **scan:** The config value `scan.Exclude` is now a list rather than a string.
* **check:** Renamed the `check` command to `deps`.
* The config value `scan.Include` is now a list rather than a string.

### Features

* Added new `check` command. ([cbd74f3](https://github.com/sbrow/envr/commit/cbd74f387e2e330b2557d07dd82ba05cc91300ac))
* **config:** The default config now filters out more junk. ([15be62b](https://github.com/sbrow/envr/commit/15be62b5a2a5a735b90b074497d645c5a2cfced8))
* **init:** Added a `--force` flag for overwriting an existing config. ([169653d](https://github.com/sbrow/envr/commit/169653d7566f63730fb9da80a18330a566223be9))
* Multiple scan includes are now supported. ([4273fa5](https://github.com/sbrow/envr/commit/4273fa58956d8736271a0af66202dca481126fe4))
* **scan:** Added support for multiple exports. ([f43705c](https://github.com/sbrow/envr/commit/f43705cd53c6d87aef1f69df4e474441f25c1dc7))
* **sync:** envr can now detect if directories have moved. ([4db0a4d](https://github.com/sbrow/envr/commit/4db0a4d33d2b6a79d13b36a8e8631f895e8fef8d))
* **sync:** Now checks files for mismatched hashes before replacing. ([8074f7a](https://github.com/sbrow/envr/commit/8074f7ae6dfa54e931a198257f3f8e6d0cfe353a))


### Bug Fixes

* **check:** `fd` now correctly gets marked as found. ([17ce49c](https://github.com/sbrow/envr/commit/17ce49cd2d33942282c6f54ce819ac25978f6b7c))


### Code Refactoring

* **check:** Renamed the `check` command to `deps`. ([c9c34ce](https://github.com/sbrow/envr/commit/c9c34ce771653da214635f1df1fef1f23265c552))
* Dir is no longer stored in the database. ([0fef74a](https://github.com/sbrow/envr/commit/0fef74a9bba0fbf3c34b66c2095955e6eee7047b))

## [0.1.1](https://github.com/sbrow/envr/compare/v0.1.0...v0.1.1) (2025-11-05)


### Features

* **sync:** Results are now displayed in a table. ([42796ec](https://github.com/sbrow/envr/commit/42796ec77b1817e1b9f09068d76a7b6e30da246b))


### Bug Fixes

* **sync:** Fixed an issue where deleted folders would be restored. ([9ab72a2](https://github.com/sbrow/envr/commit/9ab72a25faf1af0eedb2f4574166c6ee47450ebb))
