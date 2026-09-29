# koha-plugin-file-transport-webdav — design

## Background

Bug 43666 (`Koha::Objects::Mixin::SingleTableInheritance::Pluggable`, built on
bug 43663) lets a Koha plugin register additional Single Table Inheritance
subclasses against an opted-in `Koha::Objects` plural class, gated by a
koha-conf.xml kill-switch and a per-plugin-per-target-class toggle in the
Plugin management UI. `Koha::File::Transports` is bug 43666's own proving
ground: it opts into `::Pluggable`, but ships no plugin-contributed transport
type of its own.

This repo is that missing piece: a real, standalone Koha plugin delivering a
WebDAV `Koha::File::Transport` backend, with full feature parity to the
existing core `SFTP`/`FTP`/`Local` transports. Its purpose is twofold:

1. Give the bug 43666 mechanism a genuine, non-trivial consumer to prove the
   end-to-end path actually works and is worth the complexity it adds.
2. Serve as the reference example linked from bug 43666's own Bugzilla
   comments for anyone wanting to build their own pluggable transport (or
   trial a class before proposing it for core).

Per bug 43666's own design doc (`core/notes/2026-09-29-pluggable-sti-classing-design.md`,
section 6 and 7), this plugin is deliberately a *separate* deliverable — not
bundled into bug 43666's own commit series — and is written to the exact
`Koha::File::Transport` base-class interface so that, if it proves itself, it
can be promoted into core with a pure file-move (see "Promotion path" below).

## Explicitly out of scope

- Any change to `Koha::Objects::Mixin::SingleTableInheritance::Pluggable`,
  `Koha::Plugins::Base`, or any other bug 43666/43663 core code — this repo
  only *consumes* that mechanism.
- A plugin `configure`/`tool` settings page. Every connection setting (host,
  port, credentials, directories) already exists on `file_transports` and is
  managed entirely through core's own Administration > File transports UI,
  exactly as it already is for SFTP/FTP/Local. This plugin has nothing of its
  own to configure.
- Digest auth, client TLS certificates, or any WebDAV extension beyond plain
  `PROPFIND`/`GET`/`PUT`/`MOVE` (locking, versioning, ACL). Feature parity
  with SFTP/FTP/Local does not require these; YAGNI until a real use case
  needs them.
- A generic plugin-owned config block (e.g. for a TLS-verification flag) —
  noted as a possible future addition (see "TLS verification" below) but not
  built now.

## Design

### 1. Repo & module layout

Scaffolded from `koha-plugin-template` (same conventions as every sibling
plugin under `~/Projects/koha/plugins/`: `package.json`-driven versioning,
`CHANGELOG.md`, the template's GitHub Actions test+release workflow producing
a `.kpz` on tag push).

- **Entry point** (the installable plugin, `Koha::Plugins::Base` subclass):
  `Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm`, class
  `Koha::Plugin::Com::OpenFifth::FileTransportWebDAV`. Its only functional
  job is `additional_sti_classes()`:

  ```perl
  sub additional_sti_classes {
      return {
          'Koha::File::Transports' =>
              ['Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV'],
      };
  }
  ```

  No `configure`/`tool` pages, no plugin-owned settings — see "Explicitly out
  of scope" above.

- **Transport subclass** (the STI-contributed class):
  `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm`, class
  `Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV`. Deliberately
  mirrors core's own `Koha/File/Transport/WebDAV.pm` naming one-to-one, just
  prefixed with `Plugin::Com::OpenFifth::` — chosen specifically so that a
  future promotion into core is a prefix-strip file move, nothing else (see
  "Promotion path"). `use base qw(Koha::File::Transport)`; declares
  `sub _sti_key { return 'webdav' }`.

  These are necessarily two separate class hierarchies
  (`Koha::Plugins::Base` vs `Koha::Object`/`Koha::File::Transport`) and so
  are necessarily two files, regardless of naming.

### 2. WebDAV protocol implementation

Implements the same private-method contract every core transport subclass
implements (`_connect`, `_is_connected`, `_disconnect`, `_list_files`,
`_upload_file`, `_download_file`, `_rename_file`, `_current_directory`,
`_change_directory`, `_abort_operation`) — see `Koha::File::Transport::SFTP`
for the exact shape each of these must return/raise.

- **HTTP client:** `Mojo::UserAgent` (already a Koha dependency, and the
  direction Koha's own HTTP code is moving in generally) rather than
  `LWP::UserAgent` or a dedicated CPAN WebDAV client (`HTTP::DAV` was
  considered — actively enough maintained, but it's an entirely new
  dependency and its own object model would need translating into the flat
  hashref shape `list_files()` already expects anyway, so hand-rolling on a
  library Koha already ships wins).
- **`_connect`/`_is_connected`/`_disconnect`:** WebDAV is stateless HTTP —
  "connect" is really just building the base URL and doing one cheap
  `PROPFIND depth:0` against it to confirm the endpoint is reachable and
  authenticates, storing the resulting `Mojo::UserAgent` instance in
  `$self->{connection}` (matching the SFTP/FTP pattern of stashing transport
  state directly on the blessed hashref). `_is_connected` is then just "do we
  have that instance and did the last request not error".
- **`_list_files` via `PROPFIND`:** request body
  `<D:propfind><D:allprop/></D:propfind>`, header `Depth: 1`. Response is a
  multistatus XML document parsed with `Mojo::DOM` (bundled with
  Mojolicious — no new dependency). Each `<D:response>` becomes one entry in
  the returned arrayref, in the same shape FTP/SFTP already normalise to:
  - `filename` — last path segment of `<D:href>`
  - `longname` — the raw `<D:href>` value (informational only, matching how
    SFTP's `longname` is server-supplied free text)
  - `size` — `<D:getcontentlength>`, `undef` if absent (e.g. on collections)
  - `mtime` — `<D:getlastmodified>`, parsed via `HTTP::Date::str2time`
    (already a Koha dependency)
  - `perms` — always `undef`; WebDAV has no POSIX permission concept, and
    `Koha::File::Transport::SFTP::_list_files` already leaves fields
    `undef` when a backend has nothing to report for them
  - `type` — `'directory'` if `<D:resourcetype><D:collection/></D:resourcetype>`
    is present, else `'file'`
  - The entry for the requested collection itself (the first `<D:response>`,
    whose `<D:href>` matches the request path) is skipped, matching how
    SFTP/FTP already exclude `.`/`..` from their own listings.
- **`_upload_file`/`_download_file`:** plain `PUT`/`GET` against
  `<base>/<remote_file>`.
- **`_rename_file`:** `MOVE` with a `Destination:` header set to the
  absolute destination URL within the same collection.
- **`_current_directory`/`_change_directory`:** WebDAV has no server-side
  "current working directory" concept, so this is tracked client-side as a
  path-prefix string, exactly like `Koha::File::Transport::Local` already
  does. Starts from `upload_directory`/`download_directory` if the transport
  row has one configured, else `/`.
- **Host/scheme handling (no core schema change):** `host` is interpreted as
  a full base URL when it already starts with `http://` or `https://` (e.g.
  `https://dav.example.com:8443/remote.php/dav/files/martin/`); otherwise
  it's a bare hostname and the base URL is built as `https://<host>:<port>/`
  — HTTPS is always the implicit default for a bare host, so plain HTTP
  requires spelling it out explicitly in the `host` field. The `port`
  column's DB default (`22`, inherited from the schema's SFTP-oriented
  default) is cosmetically wrong for WebDAV but harmless: the admin sets it
  per-transport already, the same way they must for FTP's port 21 vs SFTP's
  port 22.
- **Auth:** HTTP Basic, via the existing `user_name`/`plain_text_password`
  base-class fields — the same fields SFTP/FTP already reuse for their own
  auth. No new columns.
- **TLS verification:** the KTD test container (see below) uses a
  self-signed cert. Rather than add a core schema column for a
  WebDAV-specific "skip TLS verification" flag, this plugin reuses the
  existing `debug` column on `file_transports`: when `debug` is on, TLS
  certificate verification is also disabled for this transport, alongside
  whatever else `debug` already surfaces. This is plugin-specific behaviour
  layered onto a core-owned column, not a core convention, and is documented
  clearly in this repo's own `README.md`/`CLAUDE.md` rather than implied.
  A more generic plugin-owned config block for this (e.g. along the lines of
  the pluggable email transport work's own config block) is a reasonable
  future addition if a real need for finer-grained control shows up, but is
  not built now — YAGNI.

### 3. KTD test server integration

A `bytemark/webdav` service added to the `bug_43666` KTD instance's
docker-compose override (dev/test infra local to this feature work, not
core KTD):

```yaml
webdav:
  image: bytemark/webdav
  environment:
    AUTH_TYPE: Basic
    USERNAME: koha
    PASSWORD: koha
    SSL_CERT: selfsigned
  ports:
    - "8443:443"
```

Reachable from the `koha` container at `https://webdav:443/` (compose
service-name DNS) and from the host at `https://localhost:8443/` for manual
`curl`/browser sanity checks. The self-signed cert is exactly what the
`debug`-gated TLS-skip (section 2) is for — this container would otherwise
be unusable without importing a CA cert into KTD's trust store.

Public WebDAV test servers (`dlp-test.com/webdav_pub/`,
`webdavserver.com`) were considered and rejected for the real end-to-end
testing: both are third-party services outside our control, not
appropriate to build a repeatable, documented test plan around, and the
design spec's own librarian test plan already anticipates "a real **or
local** WebDAV server."

### 4. Testing strategy

- **Automated (`t/00-load.t` per the template convention, plus
  `t/Transport/WebDAV.t`):** mocks `Mojo::UserAgent` request/response calls
  via `Test::MockModule`, returning canned `Mojo::Message::Response`
  objects. Covers:
  - `_list_files` PROPFIND-response parsing, with fixture XML bodies for an
    empty collection, a mix of files and subdirectories, and a server that
    omits `getcontentlength` on collection entries.
  - `_upload_file`/`_download_file`/`_rename_file` request shape (method,
    URL, headers).
  - The host/scheme parsing logic in isolation — pure string logic, no
    network mocking needed.
- **Manual, end-to-end** against the KTD `webdav` container: exercises bug
  43666's own librarian test plan (already fully drafted in its design doc)
  — kill-switch off/on, plugin install, per-target toggle on/off, actually
  creating a `transport='webdav'` row and listing/uploading/downloading/
  renaming a real file against the container, toggling the permission back
  off and confirming the row falls back to generic `Koha::File::Transport`
  behaviour rather than erroring. This is a manual walkthrough (by us, now),
  not a CI-gated Cypress suite — matching how bug 43666's own test plan
  already frames this step as librarian-facing, not automated.

### 5. Promotion path

Per bug 43666's own design doc, promoting a plugin-trialled transport into
core is meant to be simple: move the `.pm` file, add its class name to the
target's `_sti_classes` list, done — *provided* the subclass never reached
for plugin-specific helpers (`$self->store_data`, `bundle_path`, etc. from
`Koha::Plugins::Base`). This plugin's transport subclass deliberately never
does: it is written exactly as a core subclass would be, using only the
`Koha::File::Transport` base-class interface. The one-to-one namespace
mirroring in section 1 makes the eventual move a pure prefix-strip:

1. Move `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm` to
   `Koha/File/Transport/WebDAV.pm`, unchanged.
2. Add `'Koha::File::Transport::WebDAV'` to `Koha::File::Transports`'s own
   `_sti_classes` list (one line).
3. Nothing else — dispatch is driven purely by the persisted
   `transport='webdav'` discriminator value, never by which mechanism
   supplied the class, so existing rows resolve to the newly-core-shipped
   class transparently.

## Relationship to other in-flight work

- Bug 43666 (`Koha::Objects::Mixin::SingleTableInheritance::Pluggable`) is
  the mechanism this plugin proves out; not modified by this repo.
- Bug 43663 (`Koha::Objects::Mixin::SingleTableInheritance`) is the
  foundation bug 43666 sits on; not modified by this repo either.
