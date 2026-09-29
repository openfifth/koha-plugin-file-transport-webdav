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

See `docs/superpowers/specs/2026-09-29-webdav-file-transport-design.md`
for the full design, and `CLAUDE.md` for module layout and conventions.

## Features

- Automated version management
- Automated CHANGELOG promotion (`[Unreleased]` → dated version section)
- GitHub Actions workflow for testing and releasing
- Automated KPZ file creation
- Support for multiple Koha versions (main, stable, oldstable)
- Automated GitHub releases

## Prerequisites

- Node.js and npm (for local development and version management)

## Setup

1. Clone this repository
2. Update the plugin metadata in your .pm file:
   ```perl
   our $metadata = {
       name            => 'Your Plugin Name',
       author          => 'Your Name',
       description     => 'Description of your plugin',
       date_authored   => 'YYYY-MM-DD',
       date_updated    => 'YYYY-MM-DD',
       minimum_version => $MINIMUM_VERSION,
       maximum_version => undef,
       version         => $VERSION,
   };
   ```
3. Update the `package.json` file with your plugin's information:
   ```json
   {
       "plugin": {
           "module": "Koha::Plugin::Com::OpenFifth::FileTransportWebDAV",
           "pm_path": "Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm"
       },
       "version": "1.0.0",
       "previous_version": "0.0.0"
   }
   ```
4. Update the placeholder repository URL in `CHANGELOG.md` (the `[Unreleased]` link at the bottom currently points at `YOUR_ORG/YOUR_REPO`)
5. Install dependencies:
   ```bash
   npm install
   ```

   The template ships with an empty `package.json`/`package-lock.json` (no
   dependencies) — that's expected, since most plugins add their own tooling
   later. CI installs with `npm ci`, which requires the lockfile to stay in
   sync with `package.json`; whenever you add a dependency, run
   `npm install <pkg>` (not just edit `package.json` by hand) so
   `package-lock.json` is regenerated and committed alongside it.

## Usage

### Version Management

The template includes a version management system that automatically increments versions. To update the version:

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
2. Update both version and previous_version in package.json
3. Update the version in your plugin's .pm file
4. Promote the `[Unreleased]` section in `CHANGELOG.md` to a dated `[X.Y.Z]` section, insert a fresh empty `[Unreleased]` heading, and refresh the comparison links (skipped if `CHANGELOG.md` does not exist)

### Creating Releases

To create a release:

```bash
# For a patch release
npm run release:patch

# For a minor release
npm run release:minor

# For a major release
npm run release:major
```

Before touching any files, the script checks that you're on `main`, the
working tree is clean, and local `main` is up to date with `origin/main` —
it aborts before bumping anything if any of those isn't true, so a failed
push never leaves a stray local commit/tag behind.

This will then:
1. Bump the version
2. Create a git commit
3. Create a git tag
4. Push to GitHub

The GitHub Actions workflow will then:
1. Run tests against multiple Koha versions
2. Create a KPZ file for your plugin
3. Create a GitHub release with the KPZ file and CHANGELOG.md

### Testing

The workflow runs tests against three Koha versions:
- main (development)
- stable (current stable release)
- oldstable (previous stable release)

Tests are run using koha-testing-docker in the GitHub Actions environment.

## Customization

You can customize the workflow by:

1. Modifying the test matrix in `.github/workflows/main.yml`
2. Adding additional test steps
3. Customizing the release process
4. Modifying the version increment logic in `increment_version.js`

## Testing against a real WebDAV server

`compose/webdav.yml` adds a `bytemark/webdav` service (Basic auth,
self-signed TLS) to a running KTD instance, for real end-to-end testing
of this plugin's transport (rather than the public test WebDAV servers
that exist on the internet, which are third-party services not
appropriate to build a repeatable test plan around).

Bring it up alongside a KTD instance that also has this plugin mounted:

```bash
ktd --name bug_43666 --single-plugin "$(pwd)" -f "$(pwd)/compose/webdav.yml" up -d
```

Reachable from the `koha` container at `https://webdav:443/` (compose
service-name DNS) and from the host at `https://localhost:8443/` for
manual `curl`/browser sanity checks. Credentials: `koha`/`koha`.

Because the cert is self-signed, a `file_transports` row pointed at this
container needs its `debug` flag on (see `Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV::_ua`)
to skip TLS verification - this is a test-only convenience, not a recommendation
for production WebDAV endpoints, which should use a properly-signed certificate
and leave `debug` off.

## Maintenance

The `release` job pins `bywatersolutions/github-action-koha-plugin-create-kpz`
to a specific tagged release (currently `@v3`) rather than a floating branch,
so a release build only picks up a new version of that action when you
deliberately bump the pin. Check
[its releases](https://github.com/bywatersolutions/github-action-koha-plugin-create-kpz/releases)
occasionally and update the `uses:` line in `.github/workflows/main.yml` when
a new major version ships.

## License

This template is licensed under the GPL-3.0 license.