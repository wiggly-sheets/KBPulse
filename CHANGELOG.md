# Changelog

All notable changes to KBPulse are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The repository now offers the shared build interface of the estate:
  `make build`, `test`, `verify`, `app`, `install`, `run`, `dmg`,
  `release-artifacts`, `release-notes` and `release`. `make run` installs the
  ad-hoc signed app into `~/Applications` and launches it.
