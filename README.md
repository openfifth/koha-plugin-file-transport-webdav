# koha-plugin-file-transport-webdav

Adds a WebDAV backend to Koha's Administration > File transports, via bug
43666's pluggable Single Table Inheritance registration mechanism
(`Koha::Objects::Mixin::SingleTableInheritance::Pluggable`). Serves as the
reference example for that mechanism, linked from bug 43666's own Bugzilla
comments.

**Requires** a Koha instance with bug 43663 and bug 43666 applied - neither
is in any released Koha version yet. Installing this plugin alone has no
visible effect: it also requires the `enable_plugin_sti_registration`
koha-conf.xml kill-switch on, and this plugin explicitly permitted for
`Koha::File::Transports` in the Plugin management UI - both off by default.

Every connection setting (host, port, credentials, TLS behaviour) already
exists on `file_transports` and is managed through core's own
Administration > File transports UI - this plugin has no `configure`/`tool`
pages of its own.

## Installation

Download the latest KPZ from this repository's
[Releases](https://github.com/openfifth/koha-plugin-file-transport-webdav/releases)
page and install it via Koha's Administration > Manage plugins > Upload
plugin, then enable it as described above.

## Documentation

- `docs/superpowers/specs/2026-09-29-webdav-file-transport-design.md` -
  the full design, including the promotion path into core
- `CLAUDE.md` - module layout and WebDAV protocol conventions
- `DEVELOPMENT.md` - setup, version management, releases, and testing for
  developers working on this plugin

## License

This plugin is licensed under the GPL-3.0 license.
