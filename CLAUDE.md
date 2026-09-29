# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Koha plugin (`Koha::Plugin::Com::OpenFifth::FileTransportWebDAV`) that adds
a WebDAV backend to Administration > File transports, via bug 43666's
pluggable Single Table Inheritance registration mechanism
(`Koha::Objects::Mixin::SingleTableInheritance::Pluggable`). It is the
reference example for that mechanism - not a bug fix or an independent
feature - and requires bug 43663 + bug 43666 applied to work at all.

This repo is one of several sibling Koha plugin packages under
`~/Projects/koha/plugins/`; see `~/Projects/koha/CLAUDE.md` for the overall
monorepo layout and the `kd` worktree/KTD workflow.

## Module layout

- `Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm` - the installable
  plugin entry point (`Koha::Plugins::Base` subclass). Its only functional
  job is `additional_sti_classes()`. No `configure`/`tool` pages - every
  connection setting already exists on `file_transports` and is managed
  through core's own Administration > File transports UI.
- `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm` - the actual
  transport subclass (`Koha::File::Transport` subclass, `_sti_key =>
  'webdav'`). Deliberately namespaced to mirror where it would live in
  core (`Koha::File::Transport::WebDAV`) one-to-one, so promotion is a
  pure prefix-strip file move - see the design spec's "Promotion path"
  section. Never uses a plugin-specific helper (`store_data`,
  `bundle_path`, etc.) - only the `Koha::File::Transport` base-class
  interface.

## WebDAV protocol conventions

- HTTP client: `Mojo::UserAgent`. `_list_files` issues `PROPFIND Depth:
  1` and parses the multistatus XML response with `Mojo::DOM`, after
  stripping namespace prefixes (`D:`, `d:`, or none) via regex, since
  different WebDAV servers use different prefixes for the same `DAV:`
  namespace.
- `host` is a full base URL when it starts with `http://`/`https://`;
  otherwise a bare hostname, defaulting to `https://<host>:<port>/` -
  HTTPS is always the implicit default; plain HTTP requires an explicit
  `http://` prefix in the `host` field.
- TLS certificate verification is skipped only when the transport row's
  `debug` flag is on (`Koha::Plugin::Com::OpenFifth::File::Transport::
  WebDAV::_ua`) - there is no dedicated column for this, and adding one
  is out of scope for a plugin. This exists for the self-signed cert on
  the KTD test container (see below); leave `debug` off against a real
  WebDAV endpoint with a properly-signed certificate.
- `_current_directory`/`_change_directory` track a path client-side
  (`{current_directory}` on the blessed hashref), exactly like
  `Koha::File::Transport::Local` does - WebDAV has no server-side
  "current working directory" concept.

## Testing

- `t/00-load.t` (template convention): loads the plugin module,
  instantiates it, checks `$plugin->{metadata}->{version}` matches
  `package.json`.
- `t/Transport/WebDAV.t`: mocks `Mojo::UserAgent` via `Test::MockModule`
  - no real network access, safe for CI. Covers PROPFIND-response
  parsing (empty collection, mixed files/subdirectories, a server
  omitting `getcontentlength` on collections), `_upload_file`/
  `_rename_file` request shape, and `_base_url`'s host/scheme parsing in
  isolation.
- `compose/webdav.yml` adds a real `bytemark/webdav` KTD test service
  for manual end-to-end verification (not part of the automated suite -
  see `README.md`'s "Testing against a real WebDAV server" section).

CI (`.github/workflows/main.yml`, inherited from `koha-plugin-template`)
runs the automated suite against `main`/`stable`/`oldstable` Koha
versions - but since bug 43663/43666 aren't in any released Koha version
yet, only the `main` matrix leg can actually install this plugin's
`additional_sti_classes()` contribution meaningfully; `stable`/`oldstable`
legs will still load and unit-test the module (mocked, no core dependency)
but cannot exercise real STI registration until those bugs are released.

## Promotion path

See the design spec's own "Promotion path" section
(`docs/superpowers/specs/2026-09-29-webdav-file-transport-design.md`) -
moving `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm` into core as
`Koha/File/Transport/WebDAV.pm` plus one line added to `Koha::File::
Transports`'s `_sti_classes` is the entire promotion, provided this class
never starts reaching for plugin-specific helpers.
