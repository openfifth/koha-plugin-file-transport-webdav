# Development

Guidance for developers working on this plugin itself - version bumps,
releases, and running the test suite. For what the plugin does and how to
install it, see `README.md`. For module layout and WebDAV protocol
conventions, see `CLAUDE.md`.

## Prerequisites

- Node.js and npm (for version management and release tooling)
- A Koha dev environment for integration testing - see the monorepo root
  `CLAUDE.md` for the `kd`/KTD workflow

## Setup

```bash
git clone git@github.com:openfifth/koha-plugin-file-transport-webdav.git
cd koha-plugin-file-transport-webdav
npm install
```

`npm ci` (used in CI) requires the lockfile to stay in sync with
`package.json` - whenever you add a dependency, run `npm install <pkg>`
(not just edit `package.json` by hand) so `package-lock.json` is
regenerated and committed alongside it.

## Running the test suite

- `t/00-load.t` loads the plugin module, instantiates it, and checks
  `$plugin->{metadata}->{version}` matches `package.json`.
- `t/Transport/WebDAV.t` mocks `Mojo::UserAgent` via `Test::MockModule` -
  no real network access required. Covers PROPFIND-response parsing,
  `_upload_file`/`_rename_file` request shape, and `_base_url`'s
  host/scheme parsing.

Run inside a KTD container with this plugin mounted (see
`koha-prove` in the monorepo's Koha contributor tooling), e.g.:

```bash
prove -v t/00-load.t t/Transport/WebDAV.t
```

## Testing against a real WebDAV server

`compose/webdav.yml` adds a `bytemark/webdav` service (Basic auth) to a
running KTD instance, for real end-to-end testing of this plugin's
transport (rather than the public test WebDAV servers that exist on the
internet, which are third-party services not appropriate to build a
repeatable test plan around).

Bring it up alongside a KTD instance that also has this plugin mounted:

```bash
ktd --name bug_43666 --single-plugin "$(pwd)" -f "$(pwd)/compose/webdav.yml" up -d
```

Reachable from the `koha` container at `http://webdav:80/` (compose
service-name DNS) and from the host at `http://localhost:8090/` for
manual `curl`/browser sanity checks. Credentials: `koha`/`koha`.

**Plain HTTP only, verified against a live KTD instance.** The design
originally called for `SSL_CERT: selfsigned` so this container could also
exercise the `debug` flag's TLS-verification-skip path (see
`Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV::_ua`) end-to-end.
In practice, `bytemark/webdav` is an unmaintained ~2018 Alpine 3.8 image
(both its `latest` and `2.4` tags are identical and equally old) whose
bundled `mod_ssl.so` fails to load against its own bundled `libssl`
("`Error relocating .../mod_ssl.so: SSL_CTX_set_post_handshake_auth:
symbol not found`") - a known, unfixed upstream bug
(BytemarkHosting/docker-webdav#52), not something specific to this host.
There is no other tag to pin to, so this test container cannot serve
HTTPS at all; a `file_transports` row pointed at it should therefore use
a plain `http://webdav/` `host` value and leave `debug` off. The `debug`/
TLS-skip code path itself (`$ua->insecure(1) if $self->debug`) is still
implemented in `_ua`, but neither this real test container nor
`t/Transport/WebDAV.t`'s mocked tests currently exercise it - it's
untested code, pending either a TLS-capable test server or a dedicated
unit test that mocks `$self->debug`. Real HTTPS WebDAV endpoints with a
properly-signed certificate are unaffected by this container's SSL bug;
`debug` remains intended as a test-only convenience for self-signed certs
on servers that actually support TLS.

## Version management

To update the version:

```bash
# For a patch version bump (1.0.0 -> 1.0.1)
npm run version:patch

# For a minor version bump (1.0.0 -> 1.1.0)
npm run version:minor

# For a major version bump (1.0.0 -> 2.0.0)
npm run version:major
```

This will:
1. Increment the version number
2. Update both `version` and `previous_version` in `package.json`
3. Update the version in the plugin's `.pm` file
4. Promote the `[Unreleased]` section in `CHANGELOG.md` to a dated
   `[X.Y.Z]` section, insert a fresh empty `[Unreleased]` heading, and
   refresh the comparison links

## Creating releases

```bash
# For a patch release
npm run release:patch

# For a minor release
npm run release:minor

# For a major release
npm run release:major
```

Before touching any files, the script checks that you're on `main`, the
working tree is clean, and local `main` is up to date with `origin/main` -
it aborts before bumping anything if any of those isn't true, so a failed
push never leaves a stray local commit/tag behind.

This will then:
1. Bump the version
2. Create a git commit
3. Create a git tag
4. Push to GitHub

The GitHub Actions workflow will then:
1. Run tests against multiple Koha versions
2. Create a KPZ file for the plugin
3. Create a GitHub release with the KPZ file and `CHANGELOG.md`

### CI test matrix

`.github/workflows/main.yml` runs tests against three Koha versions:
- main (development)
- stable (current stable release)
- oldstable (previous stable release)

using koha-testing-docker in the GitHub Actions environment. Since bug
43663/43666 aren't in any released Koha version yet, only the `main`
matrix leg can actually install this plugin's `additional_sti_classes()`
contribution meaningfully; `stable`/`oldstable` legs still load and
unit-test the module (mocked, no core dependency) but can't exercise real
STI registration until those bugs are released.

## Customization

You can customize the workflow by:

1. Modifying the test matrix in `.github/workflows/main.yml`
2. Adding additional test steps
3. Customizing the release process
4. Modifying the version increment logic in `increment_version.js`

## Maintenance

The `release` job pins `bywatersolutions/github-action-koha-plugin-create-kpz`
to a specific tagged release (currently `@v3`) rather than a floating branch,
so a release build only picks up a new version of that action when you
deliberately bump the pin. Check
[its releases](https://github.com/bywatersolutions/github-action-koha-plugin-create-kpz/releases)
occasionally and update the `uses:` line in `.github/workflows/main.yml` when
a new major version ships.
