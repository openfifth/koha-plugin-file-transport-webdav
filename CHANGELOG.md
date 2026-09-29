# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Add user-visible changes under the `[Unreleased]` heading below as you work.
On the next `npm run release:*`, `increment_version.js` promotes `[Unreleased]`
to a dated `[X.Y.Z]` section and inserts a fresh empty `[Unreleased]` above it
along with the comparison links — do not edit the heading or the links by hand.

## [Unreleased]

## [0.1.2] - 2026-09-29

## [0.1.1] - 2026-09-29

### Added

- WebDAV file transport backend (`Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV`), registered against `Koha::File::Transports` via bug 43666's pluggable Single Table Inheritance mechanism.

### Changed

### Fixed

- `check_release_ready.js`'s sync check compared local `main` and `origin/main` for exact SHA equality, so it wrongly blocked a release whenever local had *any* unpushed commit — including the normal case of committing fixes locally and then releasing, which pushes them. Use `git merge-base --is-ancestor origin/main main` instead, which only fails when local is genuinely behind or diverged.

[Unreleased]: https://github.com/openfifth/koha-plugin-file-transport-webdav/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/openfifth/koha-plugin-file-transport-webdav/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/openfifth/koha-plugin-file-transport-webdav/compare/v0.1.0...v0.1.1