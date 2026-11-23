# Changelog

All notable changes to KBPulse are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A split-view theme editor with a theme sidebar, live preview, identity card,
  visual animation timelines, brightness sliders, typing-reaction controls and
  reaction curves.
- A shared Theme model and codec. The editor, import and CLI use the same
  validation rules, and unknown keys and fractional durations are preserved.
- A preview session that plays the edited document in memory, restores the
  active theme and supports cancelling.
- `kbpulse list` and `kbpulse validate`, sharing the app theme schema and
  directory. `kbpulse help` prints usage.
- The repository offers the shared build interface of the estate:
  `make build`, `test`, `verify`, `app`, `install`, `run`, `dmg`,
  `release-artifacts`, `release-notes` and `release`. `make run` installs the
  ad-hoc signed app into `/Applications` and launches it.

### Changed

- Theme files now live in `~/Library/Application Support/KBPulse`. The CLI no
  longer reads `~/Documents/KBPulse`; move old themes manually.
- Animations use fractional milliseconds and fade-then-hold timing shared by
  playback and the brightness curve.
- The settings window opens at 860x640 and can be resized.
- Import failures list every validation issue.

### Fixed

- The editor marks changes against a saved snapshot, so loading a theme or
  clearing the selection no longer produces a false dirty state.
- Animation name and millisecond fields no longer show duplicate labels.
- `kbpulse help` exits successfully.
