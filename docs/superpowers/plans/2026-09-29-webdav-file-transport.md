# WebDAV File Transport Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real, standalone Koha plugin (`koha-plugin-file-transport-webdav`) that delivers a WebDAV `Koha::File::Transport` backend with full feature parity to core's SFTP/FTP/Local transports, proving out bug 43666's pluggable Single Table Inheritance registration mechanism end-to-end.

**Architecture:** Two plugin-owned classes: a thin `Koha::Plugins::Base` entry point whose only job is declaring the contributed class via `additional_sti_classes()`, and a `Koha::File::Transport` subclass implementing the full transport contract (`_connect`/`_list_files`/`_upload_file`/`_download_file`/`_rename_file`/`_change_directory`/`_current_directory`/`_is_connected`/`_disconnect`) against a real WebDAV server using `Mojo::UserAgent`, mirroring `Koha::File::Transport::SFTP`/`Koha::File::Transport::Local`'s exact patterns for messages, errors, and directory tracking.

**Tech Stack:** Perl 5, `Mojo::UserAgent`/`Mojo::DOM`/`Mojo::URL` (Mojolicious, already a Koha dependency), `HTTP::Date`, `Test::MockModule`/`Test::More`, Docker (`bytemark/webdav` KTD test service), KTD (`koha-testing-docker`).

**Spec:** `docs/superpowers/specs/2026-09-29-webdav-file-transport-design.md`

## Global Constraints

- `_sti_key` for the contributed transport is exactly `'webdav'` (per spec).
- The transport subclass must use ONLY the `Koha::File::Transport` base-class interface — never plugin-specific helpers (`$self->store_data`, `bundle_path`, etc. from `Koha::Plugins::Base`) — to keep the promotion-to-core path a pure file move (per spec section 5).
- `host` is a full base URL when it starts with `http://`/`https://`; otherwise a bare hostname, and the base URL defaults to `https://<host>:<port>/` — HTTPS is always the implicit default (per spec section 2).
- TLS certificate verification is skipped only when the transport row's `debug` column is true (per spec section 2) — no new database column.
- No change to any bug 43666/43663 core file — this repo only consumes `additional_sti_classes()` (per spec, "Explicitly out of scope").
- No plugin `configure`/`tool` settings page — every connection setting already exists on `file_transports` and is managed through core's own admin UI (per spec, "Explicitly out of scope").
- No Bugzilla/bug-filing steps — this plugin is referenced from bug 43666's comments, not attached to any bug (per spec).

---

### Task 1: Entry-point plugin class

**Files:**
- Create: `Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm`
- Delete: `Koha/Plugin/Com/Organisation/PluginName.pm`
- Delete: `Koha/Plugin/Com/Organisation/PluginName/templates/configure.tt`
- Delete: `Koha/Plugin/Com/Organisation/PluginName/templates/tool.tt`
- Modify: `package.json`
- Test: `t/00-load.t` (already exists, generic — no changes needed, just verify it passes against the new module)

**Interfaces:**
- Produces: `Koha::Plugin::Com::OpenFifth::FileTransportWebDAV->new()`, `->additional_sti_classes()` returning `{ 'Koha::File::Transports' => ['Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV'] }`. Task 2's transport class must be named exactly this string.

- [ ] **Step 1: Remove the template's placeholder plugin class and its templates**

```bash
rm -rf Koha/Plugin/Com/Organisation
```

- [ ] **Step 2: Create the entry-point plugin class**

Write `Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm`:

```perl
package Koha::Plugin::Com::OpenFifth::FileTransportWebDAV;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use base qw(Koha::Plugins::Base);

our $VERSION         = '0.1.0';
our $MINIMUM_VERSION = "24.11.00.000";

our $metadata = {
    name            => 'File Transport: WebDAV',
    author          => 'Martin Renvoize',
    description     =>
        'Adds a WebDAV backend to Administration > File transports, via '
        . 'the pluggable Single Table Inheritance registration mechanism '
        . '(bug 43666). Requires a Koha instance with bug 43663 and bug '
        . '43666 applied (not yet in any released version).',
    date_authored   => '2026-09-29',
    date_updated    => '2026-09-29',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
};

=head1 NAME

Koha::Plugin::Com::OpenFifth::FileTransportWebDAV - WebDAV file transport plugin

=head2 Class methods

=head3 new

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 install

=cut

sub install {
    my ( $self, $args ) = @_;
    return 1;
}

=head3 upgrade

=cut

sub upgrade {
    my ( $self, $args ) = @_;
    return 1;
}

=head3 uninstall

=cut

sub uninstall {
    my ( $self, $args ) = @_;
    return 1;
}

=head3 additional_sti_classes

Declares this plugin's contribution to Koha::File::Transports' pluggable
Single Table Inheritance registration (see
Koha::Objects::Mixin::SingleTableInheritance::Pluggable, bug 43666).

Only actually honoured for a Koha instance with the
enable_plugin_sti_registration koha-conf.xml kill-switch on AND this
plugin explicitly permitted, per-target, in the Plugin management UI -
both off by default. Installing this plugin alone has no visible effect.

=cut

sub additional_sti_classes {
    return {
        'Koha::File::Transports' =>
            ['Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV'],
    };
}

1;
```

- [ ] **Step 3: Update `package.json`**

Edit `package.json`, replacing the `plugin` block and bumping the version:

```json
{
  "plugin": {
    "module": "Koha::Plugin::Com::OpenFifth::FileTransportWebDAV",
    "pm_path": "Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm"
  },
  "version": "0.1.0",
  "previous_version": "0.0.0",
  "scripts": {
    "version:patch": "node increment_version.js patch | cat",
    "version:minor": "node increment_version.js minor | cat",
    "version:major": "node increment_version.js major | cat",
    "release:patch": "node check_release_ready.js && node increment_version.js patch | cat && PLUGIN_FILE=$(node -p 'require(\"./package.json\").plugin.pm_path') && git add package.json \"$PLUGIN_FILE\" CHANGELOG.md && git commit -m 'chore: bump version' && VERSION=$(node -p 'require(\"./package.json\").version') && git tag -a v$VERSION -m \"Release v$VERSION\" && node ensure_workflows_enabled.js && git push origin main --follow-tags",
    "release:minor": "node check_release_ready.js && node increment_version.js minor | cat && PLUGIN_FILE=$(node -p 'require(\"./package.json\").plugin.pm_path') && git add package.json \"$PLUGIN_FILE\" CHANGELOG.md && git commit -m 'chore: bump version' && VERSION=$(node -p 'require(\"./package.json\").version') && git tag -a v$VERSION -m \"Release v$VERSION\" && node ensure_workflows_enabled.js && git push origin main --follow-tags",
    "release:major": "node check_release_ready.js && node increment_version.js major | cat && PLUGIN_FILE=$(node -p 'require(\"./package.json\").plugin.pm_path') && git add package.json \"$PLUGIN_FILE\" CHANGELOG.md && git commit -m 'chore: bump version' && VERSION=$(node -p 'require(\"./package.json\").version') && git tag -a v$VERSION -m \"Release v$VERSION\" && node ensure_workflows_enabled.js && git push origin main --follow-tags"
  }
}
```

- [ ] **Step 4: Verify `t/00-load.t` passes**

`t/00-load.t` already reads `package.json`'s `plugin.module`, loads it, instantiates it, and checks `$plugin->{metadata}->{version}` matches `package.json`'s `version` — no changes needed, it's generic. It must be run inside a container with the real `Koha::Plugins::Base` available (see Task 5 for bringing up the KTD instance); note that as pending here, and re-run it as part of Task 5's final verification.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add WebDAV file transport plugin entry point"
```

---

### Task 2: WebDAV transport subclass

**Files:**
- Create: `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm`

**Interfaces:**
- Consumes: `Koha::File::Transport` base class methods `add_message({message, type, payload})`, `_record_error($operation, \%payload)`, `object_messages`, `host`, `port`, `user_name`, `plain_text_password`, `download_directory`, `upload_directory`, `debug` (all DBIx::Class column accessors or base-class methods — see `Koha::File::Transport` in the bug_43666 worktree at `/home/martin/Projects/koha/core/worktrees/bug_43666/Koha/File/Transport.pm`, and its `SFTP.pm`/`Local.pm` subclasses in the same directory for the exact contract shape).
- Produces: `Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV`, `_sti_key() == 'webdav'`, and all of `_connect`/`_is_connected`/`_disconnect`/`_list_files`/`_upload_file`/`_download_file`/`_rename_file`/`_current_directory`/`_change_directory`/`_abort_operation` — Task 3's tests call these directly.

- [ ] **Step 1: Write the failing test for host/scheme URL resolution (pure logic, no network)**

Create `t/Transport/WebDAV.t` with just this first subtest for now (Task 3 adds the rest):

```perl
use Modern::Perl;
use Test::More;
use Test::Exception;

my $plugin_dir = $ENV{KOHA_PLUGIN_DIR} || '.';
unshift @INC, $plugin_dir;

use_ok('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');

subtest '_base_url' => sub {
    plan tests => 4;

    my $bare = bless { _column_data => { host => 'dav.example.com', port => 8443 } },
        'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    is( $bare->_base_url, 'https://dav.example.com:8443/', 'bare host defaults to https' );

    my $https = bless { _column_data => { host => 'https://dav.example.com:8443/base/', port => 443 } },
        'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    is( $https->_base_url, 'https://dav.example.com:8443/base/', 'explicit https host used as-is' );

    my $http = bless { _column_data => { host => 'http://webdav:80/', port => 80 } },
        'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    is( $http->_base_url, 'http://webdav:80/', 'explicit http host used as-is (opt-in plaintext)' );

    my $no_port = bless { _column_data => { host => 'dav.example.com', port => undef } },
        'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    like( $no_port->_base_url, qr{^https://dav\.example\.com:}, 'bare host with no port still defaults to https' );
};

done_testing();
```

Note: `Koha::Object`-derived classes normally proxy column accessors (`host`, `port`, etc.) through `AUTOLOAD` reading `$self->_result->get_column(...)`. Directly `bless`-ing a hashref with `_column_data` will NOT work against the real base class's `AUTOLOAD`. Task 3 replaces this fixture approach with a `Test::MockModule`-mocked `host`/`port` instead — this first version is only to prove the test file loads and to get `_base_url`'s pure string logic named and callable; expect it to fail with "Can't locate object method" until Step 3 below exists, then adjust per Task 3 Step 1.

- [ ] **Step 2: Run test to verify it fails**

```bash
prove -v t/Transport/WebDAV.t
```

Expected: FAIL at `use_ok('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV')` — the module doesn't exist yet.

- [ ] **Step 3: Write the transport subclass**

Create `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm`:

```perl
package Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Mojo::UserAgent;
use Mojo::URL;
use Mojo::DOM;
use HTTP::Date qw( str2time );

use base qw(Koha::File::Transport);

=head1 NAME

Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV - WebDAV implementation of file transport

Written to the exact Koha::File::Transport base-class interface (see
Koha::File::Transport::SFTP / Koha::File::Transport::Local for the
reference shape) so it can be promoted into core - as
Koha::File::Transport::WebDAV - with a pure file move: no
plugin-specific helper (store_data, bundle_path, etc.) is used anywhere
in this class.

=head2 Class methods

=head3 _sti_key

Dispatch key used by Koha::File::Transports (see
Koha::Objects::Mixin::SingleTableInheritance).

=cut

sub _sti_key {
    return 'webdav';
}

=head3 _base_url

    my $url = $self->_base_url;

Returns the transport's base URL as a plain string. C<host> is used
as-is when it already looks like a URL (starts with C<http://> or
C<https://>); otherwise it's treated as a bare hostname and the base
URL is built as C<https://<host>:<port>/> - HTTPS is always the
implicit default for a bare host, so plain HTTP requires spelling it
out explicitly in the C<host> field.

=cut

sub _base_url {
    my ($self) = @_;

    my $host = $self->host // '';
    return $host if $host =~ m{^https?://}i;

    my $port = $self->port || 443;
    return sprintf( 'https://%s:%s/', $host, $port );
}

=head3 _current_path

    my $path = $self->_current_path;

Returns the path most recently set via change_directory(), falling back
to download_directory, then upload_directory, then '/'. Mirrors
Koha::File::Transport::Local's C<_working_directory>, adapted for
WebDAV having a single client-tracked path rather than separate
upload/download working directories.

=cut

sub _current_path {
    my ($self) = @_;

    return $self->{current_directory} // $self->download_directory // $self->upload_directory // '/';
}

=head3 _join_path

    my $path = $self->_join_path( $directory, $name );

Joins a directory path and a file/collection name with exactly one
slash between them.

=cut

sub _join_path {
    my ( $self, $dir, $name ) = @_;

    $dir = '/' unless defined $dir && length $dir;
    $dir .= '/' unless $dir =~ m{/$};

    return $dir . $name;
}

=head3 _url_for

    my $url = $self->_url_for( $path );

Returns a Mojo::URL for the given path (defaulting to _current_path)
against this transport's base URL, with credentials attached for Basic
auth. Mojo::URL handles percent-encoding of the path itself.

=cut

sub _url_for {
    my ( $self, $path ) = @_;

    my $target = $path // $self->_current_path;
    $target = '/' . $target unless $target =~ m{^/};

    my $url = Mojo::URL->new( $self->_base_url );
    $url->path($target);

    if ( $self->user_name ) {
        $url->userinfo( join( ':', $self->user_name, $self->plain_text_password // '' ) );
    }

    return $url;
}

=head3 _ua

    my $ua = $self->_ua;

Returns this transport's Mojo::UserAgent instance, creating it on first
use. TLS certificate verification is disabled when this transport row's
C<debug> flag is on (used for the self-signed cert on the KTD test
container - see this repo's compose/webdav.yml) - there is no dedicated
"skip TLS verification" column on file_transports, and adding one is
out of scope for a plugin (see this repo's design spec).

=cut

sub _ua {
    my ($self) = @_;

    unless ( $self->{ua} ) {
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1) if $self->debug;
        $self->{ua} = $ua;
    }

    return $self->{ua};
}

=head3 _propfind_body

Minimal PROPFIND request body requesting all properties.

=cut

sub _propfind_body {
    return '<?xml version="1.0" encoding="utf-8" ?><D:propfind xmlns:D="DAV:"><D:allprop/></D:propfind>';
}

=head3 _connect

    my $success = $self->_connect;

"Connecting" for WebDAV (a stateless HTTP protocol) means confirming
the configured URL is reachable and authenticates: a cheap
C<PROPFIND Depth: 0> against the base path.

=cut

sub _connect {
    my ($self) = @_;
    my $operation = 'connection';

    my $url = $self->_url_for('/');
    my $tx  = $self->_ua->build_tx(
        PROPFIND => $url => { Depth => 0, 'Content-Type' => 'application/xml' } => $self->_propfind_body );
    $tx = $self->_ua->start($tx);

    my $res = $tx->res;
    unless ( $res->code && $res->code == 207 ) {
        return $self->_abort_operation(
            $operation,
            {
                error  => $res->message // 'connection failed',
                status => $res->code,
                path   => $url->to_string,
            }
        );
    }

    $self->{connected} = 1;

    $self->add_message(
        {
            message => $operation,
            type    => 'success',
            payload => {
                status => $res->code,
                path   => $url->to_string,
            }
        }
    );

    return 1;
}

=head3 _is_connected

=cut

sub _is_connected {
    my ($self) = @_;

    return $self->{connected} ? 1 : 0;
}

=head3 _disconnect

WebDAV has no persistent connection to close - this just drops the
cached user agent and connected flag so the next operation
re-verifies reachability.

=cut

sub _disconnect {
    my ($self) = @_;

    delete $self->{connected};
    delete $self->{ua};

    return 1;
}

=head3 _current_directory

=cut

sub _current_directory {
    my ($self) = @_;

    return $self->_current_path;
}

=head3 _change_directory

    my $success = $self->_change_directory($remote_directory);

Confirms the target collection exists (via C<PROPFIND Depth: 0>) before
tracking it client-side - WebDAV has no server-side "current directory"
concept, so this mirrors Koha::File::Transport::Local's client-side
tracking exactly.

=cut

sub _change_directory {
    my ( $self, $remote_directory ) = @_;
    my $operation = 'change_directory';

    my $url = $self->_url_for($remote_directory);
    my $tx  = $self->_ua->build_tx(
        PROPFIND => $url => { Depth => 0, 'Content-Type' => 'application/xml' } => $self->_propfind_body );
    $tx = $self->_ua->start($tx);

    unless ( $tx->res->code && $tx->res->code == 207 ) {
        return $self->_abort_operation(
            $operation,
            {
                error  => "Directory not found: $remote_directory",
                status => $tx->res->code,
                path   => $remote_directory,
            }
        );
    }

    $self->{current_directory} = $remote_directory;

    $self->add_message(
        {
            message => $operation,
            type    => 'success',
            payload => { path => $remote_directory }
        }
    );

    return 1;
}

=head3 _list_files

Internal method that performs a PROPFIND (Depth: 1) against the
current path and returns an array reference of hashrefs with file
information: filename, longname, size, perms, mtime, type - the same
shape Koha::File::Transport::{SFTP,FTP,Local} already normalise to.

Namespace prefixes on the multistatus response vary by server (C<D:>,
C<d:>, or none with a default namespace) - they're stripped before
parsing so tag names can be matched without caring which prefix a given
server happens to use.

=cut

sub _list_files {
    my ($self) = @_;
    my $operation = 'list';

    my $url = $self->_url_for;
    my $tx  = $self->_ua->build_tx(
        PROPFIND => $url => { Depth => 1, 'Content-Type' => 'application/xml' } => $self->_propfind_body );
    $tx = $self->_ua->start($tx);

    my $res = $tx->res;
    unless ( $res->code && $res->code == 207 ) {
        return $self->_abort_operation(
            $operation,
            {
                error  => $res->message // 'PROPFIND failed',
                status => $res->code,
                path   => $url->to_string,
            }
        );
    }

    ( my $xml = $res->body ) =~ s{<(/?)[A-Za-z0-9]+:}{<$1}g;
    my $dom = Mojo::DOM->new->xml(1)->parse($xml);

    my $request_path = $url->path->to_string;
    $request_path =~ s{/+$}{} unless $request_path eq '/';

    my @files;
    for my $response ( $dom->find('response')->each ) {
        my $href_el = $response->at('href') or next;
        my $href    = $href_el->text;

        my $href_path = Mojo::URL->new($href)->path->to_string;
        $href_path =~ s{/+$}{} unless $href_path eq '/';
        next if $href_path eq $request_path;    # skip the collection itself

        my ($filename) = $href_path =~ m{([^/]+)/?$};
        next unless defined $filename;

        my $is_collection = $response->at('resourcetype collection') ? 1 : 0;
        my $size_el       = $response->at('getcontentlength');
        my $mtime_el      = $response->at('getlastmodified');

        push @files, {
            filename => $filename,
            longname => $href,
            size     => $is_collection ? undef : ( $size_el ? $size_el->text + 0 : undef ),
            perms    => undef,
            mtime    => $mtime_el ? str2time( $mtime_el->text ) : undef,
            type     => $is_collection ? 'directory' : 'file',
        };
    }

    $self->add_message(
        {
            message => $operation,
            type    => 'success',
            payload => {
                path  => $url->to_string,
                count => scalar @files,
            }
        }
    );

    return \@files;
}

=head3 _upload_file

=cut

sub _upload_file {
    my ( $self, $local_file, $remote_file ) = @_;
    my $operation = 'upload';

    open my $fh, '<:raw', $local_file
        or return $self->_abort_operation( $operation, { error => "Cannot open local file: $!", path => $local_file } );
    local $/;
    my $content = <$fh>;
    close $fh;

    my $url = $self->_url_for( $self->_join_path( $self->_current_path, $remote_file ) );
    my $tx  = $self->_ua->put( $url => {} => $content );

    unless ( $tx->res->is_success ) {
        return $self->_abort_operation(
            $operation,
            {
                error  => $tx->res->message // 'upload failed',
                status => $tx->res->code,
                path   => $url->to_string,
            }
        );
    }

    $self->add_message(
        {
            message => $operation,
            type    => 'success',
            payload => { path => $url->to_string }
        }
    );

    return 1;
}

=head3 _download_file

=cut

sub _download_file {
    my ( $self, $remote_file, $local_file ) = @_;
    my $operation = 'download';

    my $url = $self->_url_for( $self->_join_path( $self->_current_path, $remote_file ) );
    my $tx  = $self->_ua->get($url);

    unless ( $tx->res->is_success ) {
        return $self->_abort_operation(
            $operation,
            {
                error  => $tx->res->message // 'download failed',
                status => $tx->res->code,
                path   => $url->to_string,
            }
        );
    }

    my $ok = eval { $tx->res->content->asset->move_to($local_file); 1 };
    unless ($ok) {
        return $self->_abort_operation(
            $operation,
            { error => "Cannot write local file: $local_file ($@)", path => $local_file }
        );
    }

    $self->add_message(
        {
            message => $operation,
            type    => 'success',
            payload => { path => $url->to_string }
        }
    );

    return 1;
}

=head3 _rename_file

=cut

sub _rename_file {
    my ( $self, $old_name, $new_name ) = @_;
    my $operation = 'rename';

    my $source_url      = $self->_url_for( $self->_join_path( $self->_current_path, $old_name ) );
    my $destination_url = $self->_url_for( $self->_join_path( $self->_current_path, $new_name ) );

    my $tx = $self->_ua->build_tx(
        MOVE => $source_url => { Destination => $destination_url->to_string, Overwrite => 'F' } );
    $tx = $self->_ua->start($tx);

    unless ( $tx->res->is_success ) {
        return $self->_abort_operation(
            $operation,
            {
                error  => $tx->res->message // 'rename failed',
                status => $tx->res->code,
                path   => $source_url->to_string . ' -> ' . $destination_url->to_string,
            }
        );
    }

    $self->add_message(
        {
            message => $operation,
            type    => 'success',
            payload => { path => $source_url->to_string . ' -> ' . $destination_url->to_string }
        }
    );

    return 1;
}

=head3 _abort_operation

Helper method to abort the current operation and return, recording the
failure via the shared _record_error() (see Koha::File::Transport).

=cut

sub _abort_operation {
    my ( $self, $operation, $payload ) = @_;

    $self->_record_error( $operation, $payload );

    return;
}

1;
```

- [ ] **Step 4: Replace the Step 1 test fixture with a properly mocked one, and re-run**

Replace the `subtest '_base_url'` block in `t/Transport/WebDAV.t` with:

```perl
use Test::MockModule;

subtest '_base_url' => sub {
    plan tests => 4;

    my $module = Test::MockModule->new('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');

    $module->mock( host => sub { 'dav.example.com' } );
    $module->mock( port => sub { 8443 } );
    my $bare = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    is( $bare->_base_url, 'https://dav.example.com:8443/', 'bare host defaults to https' );

    $module->mock( host => sub { 'https://dav.example.com:8443/base/' } );
    my $https = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    is( $https->_base_url, 'https://dav.example.com:8443/base/', 'explicit https host used as-is' );

    $module->mock( host => sub { 'http://webdav:80/' } );
    my $http = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    is( $http->_base_url, 'http://webdav:80/', 'explicit http host used as-is (opt-in plaintext)' );

    $module->mock( host => sub { 'dav.example.com' } );
    $module->mock( port => sub { undef } );
    my $no_port = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';
    like( $no_port->_base_url, qr{^https://dav\.example\.com:}, 'bare host with no port still defaults to https (443)' );
};
```

Run:

```bash
prove -v t/Transport/WebDAV.t
```

Expected: PASS (this needs `Mojo::UserAgent`/`Mojo::URL`/`Mojo::DOM`/`HTTP::Date` importable — since these are core Koha dependencies, this passes on the host if a Koha Perl environment is available, or run inside KTD per Task 5's `KOHA_PLUGIN_DIR` convention if not).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add WebDAV Koha::File::Transport subclass"
```

---

### Task 3: Full automated test coverage

**Files:**
- Modify: `t/Transport/WebDAV.t`

**Interfaces:**
- Consumes: `Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV`'s private methods from Task 2 (`_list_files`, `_upload_file`, `_download_file`, `_rename_file`, `_connect`, `_url_for`, `_ua`), plus `Test::MockModule` mocking of `Mojo::UserAgent`'s `start`/`put`/`get`/`build_tx`.

- [ ] **Step 1: Write the failing tests for `_list_files` PROPFIND parsing**

Add to `t/Transport/WebDAV.t`, after the `_base_url` subtest:

```perl
use Mojo::Message::Response;
use Mojo::Transaction::HTTP;

sub _mock_response {
    my ($body) = @_;

    my $res = Mojo::Message::Response->new;
    $res->code(207);
    $res->headers->content_type('application/xml; charset=utf-8');
    $res->body($body);

    my $tx = Mojo::Transaction::HTTP->new;
    $tx->res($res);

    return $tx;
}

subtest '_list_files' => sub {
    plan tests => 3;

    my $ua_module = Test::MockModule->new('Mojo::UserAgent');

    $ua_module->mock(
        build_tx => sub { return Mojo::Transaction::HTTP->new },
        start    => sub {
            return _mock_response(<<'XML');
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/base/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
</D:multistatus>
XML
        }
    );

    my $module = Test::MockModule->new('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');
    $module->mock( host => sub { 'dav.example.com' }, port => sub { 443 }, user_name => sub { undef } );
    $module->mock( _current_path => sub { '/base/' } );

    my $transport = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';

    subtest 'empty collection' => sub {
        plan tests => 1;
        my $files = $transport->_list_files;
        is_deeply( $files, [], 'no entries when the multistatus response only describes the collection itself' );
    };

    $ua_module->mock(
        start => sub {
            return _mock_response(<<'XML');
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/base/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/base/subdir/</D:href>
    <D:propstat><D:prop>
      <D:resourcetype><D:collection/></D:resourcetype>
      <D:getlastmodified>Tue, 29 Sep 2026 10:00:00 GMT</D:getlastmodified>
    </D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/base/report.csv</D:href>
    <D:propstat><D:prop>
      <D:resourcetype/>
      <D:getcontentlength>1234</D:getcontentlength>
      <D:getlastmodified>Tue, 29 Sep 2026 11:00:00 GMT</D:getlastmodified>
    </D:prop></D:propstat>
  </D:response>
</D:multistatus>
XML
        }
    );

    subtest 'mixed files and subdirectories' => sub {
        plan tests => 4;
        my $files = $transport->_list_files;
        is( scalar @$files, 2, 'collection itself excluded, two entries returned' );
        my ($dir)  = grep { $_->{type} eq 'directory' } @$files;
        my ($file) = grep { $_->{type} eq 'file' } @$files;
        is( $dir->{filename}, 'subdir', 'subdirectory filename parsed from href' );
        is( $file->{filename}, 'report.csv', 'file filename parsed from href' );
        is( $file->{size}, 1234, 'file size parsed from getcontentlength' );
    };

    $ua_module->mock(
        start => sub {
            return _mock_response(<<'XML');
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/base/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/base/emptydir/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
</D:multistatus>
XML
        }
    );

    subtest 'collection entry omitting getcontentlength' => sub {
        plan tests => 2;
        my $files = $transport->_list_files;
        is( scalar @$files, 1, 'one entry returned' );
        is( $files->[0]->{size}, undef, 'size is undef for a collection with no getcontentlength' );
    };
};
```

- [ ] **Step 2: Run test to verify it fails**

```bash
prove -v t/Transport/WebDAV.t
```

Expected: FAIL — before this step, `_list_files` exists (Task 2) but has never been exercised against these exact fixtures; run it to confirm the mocks wire up correctly and surface any parsing mismatch against Task 2's implementation (e.g. namespace-stripping regex or `resourcetype collection` selector not matching as expected) before moving on.

- [ ] **Step 3: Fix any mismatch between Task 2's implementation and these fixtures**

If Step 2 fails on a selector or parsing mismatch rather than confirming real behavior, adjust `_list_files` in `Koha/Plugin/Com/OpenFifth/File/Transport/WebDAV.pm` (Task 2's file) to match — do not weaken the test fixtures to match broken code. Common culprits to check first: the namespace-stripping regex (`s{<(/?)[A-Za-z0-9]+:}{<$1}g`) must run before `Mojo::DOM->new->xml(1)->parse`, and `$response->at('resourcetype collection')` requires `Mojo::DOM`'s descendant-combinator selector (a space) to find `<collection/>` nested inside `<resourcetype>` — confirm with `perl -MMojo::DOM -e '...'` against one fixture body directly if the subtest's failure message doesn't make the cause obvious.

- [ ] **Step 4: Run test to verify it passes**

```bash
prove -v t/Transport/WebDAV.t
```

Expected: PASS, all subtests green.

- [ ] **Step 5: Write and verify `_upload_file`/`_download_file`/`_rename_file` request-shape tests**

Add to `t/Transport/WebDAV.t`:

```perl
subtest '_upload_file request shape' => sub {
    plan tests => 3;

    my ( $captured_url, $captured_body );
    my $ua_module = Test::MockModule->new('Mojo::UserAgent');
    $ua_module->mock(
        put => sub {
            my ( $self, $url, $headers, $body ) = @_;
            $captured_url  = "$url";
            $captured_body = $body;
            my $res = Mojo::Message::Response->new;
            $res->code(201);
            my $tx = Mojo::Transaction::HTTP->new;
            $tx->res($res);
            return $tx;
        }
    );

    my $module = Test::MockModule->new('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');
    $module->mock( host => sub { 'dav.example.com' }, port => sub { 443 }, user_name => sub { undef } );
    $module->mock( _current_path => sub { '/base/' } );

    my $transport = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';

    require File::Temp;
    my $tmp = File::Temp->new;
    print $tmp "hello webdav";
    close $tmp;

    my $ok = $transport->_upload_file( "$tmp", 'uploaded.txt' );
    ok( $ok, 'upload reports success' );
    is( $captured_url, 'https://dav.example.com:443/base/uploaded.txt', 'PUT issued against the current path + remote filename' );
    is( $captured_body, 'hello webdav', 'local file content sent as the request body' );
};

subtest '_rename_file request shape' => sub {
    plan tests => 3;

    my ( $captured_verb, $captured_source, $captured_headers );
    my $ua_module = Test::MockModule->new('Mojo::UserAgent');
    $ua_module->mock(
        build_tx => sub {
            my ( $self, $verb, $url, $headers ) = @_;
            $captured_verb    = $verb;
            $captured_source  = "$url";
            $captured_headers = $headers;
            return Mojo::Transaction::HTTP->new;
        },
        start => sub {
            my $res = Mojo::Message::Response->new;
            $res->code(201);
            my $tx = Mojo::Transaction::HTTP->new;
            $tx->res($res);
            return $tx;
        }
    );

    my $module = Test::MockModule->new('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');
    $module->mock( host => sub { 'dav.example.com' }, port => sub { 443 }, user_name => sub { undef } );
    $module->mock( _current_path => sub { '/base/' } );

    my $transport = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';

    my $ok = $transport->_rename_file( 'old.txt', 'new.txt' );
    ok( $ok, 'rename reports success' );
    is( $captured_verb, 'MOVE', 'MOVE verb used' );
    is(
        $captured_headers->{Destination},
        'https://dav.example.com:443/base/new.txt',
        'Destination header set to the absolute destination URL'
    );
};
```

- [ ] **Step 6: Run test to verify it passes**

```bash
prove -v t/Transport/WebDAV.t
```

Expected: PASS, all subtests green. If `_download_file`'s reliance on `Mojo::Asset`'s `move_to` is awkward to mock cleanly here, it's acceptable to leave `_download_file` covered only by the manual end-to-end walkthrough (Task 5) rather than forcing a brittle mock — note this explicitly as a comment in the test file if skipped, do not silently drop coverage without saying so.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: cover PROPFIND parsing and request shapes for the WebDAV transport"
```

---

### Task 4: KTD WebDAV test server

**Files:**
- Create: `compose/webdav.yml`
- Modify: `README.md` (add a "Testing against a real WebDAV server" section)

**Interfaces:**
- Produces: a `webdav` compose service reachable from the `koha` container at `https://webdav:443/` with Basic auth (`koha`/`koha`) and a self-signed cert, and from the host at `https://localhost:8443/`. Task 5 brings this up alongside the plugin-mounted KTD instance.

- [ ] **Step 1: Create the compose fragment**

Create `compose/webdav.yml`:

```yaml
services:
    webdav:
        image: bytemark/webdav
        environment:
            AUTH_TYPE: Basic
            USERNAME: koha
            PASSWORD: koha
            SSL_CERT: selfsigned
        ports:
            - "8443:443"
        networks:
            - kohanet

networks:
    kohanet:
        external: true
        name: ${COMPOSE_PROJECT_NAME:-bug_43666}_kohanet
```

Note: KTD's own `base.yml` defines the `kohanet` network without a project prefix override, so its actual runtime name follows Docker Compose's default `<project>_<network>` convention, where `<project>` is the KTD instance name (`bug_43666`) unless overridden. Verify the actual network name before Task 5's first run with `docker network ls | grep kohanet` once the `bug_43666` KTD instance is up, and correct the `name:` value above if it differs — do not guess past this point without checking.

- [ ] **Step 2: Document the test-server setup in README.md**

Add this section to `README.md`, replacing the template's generic content with plugin-specific documentation (Task 5 does the rest of the README rewrite; this step only adds the WebDAV-test-server section so Task 5 can reference it):

```markdown
## Testing against a real WebDAV server

`compose/webdav.yml` adds a `bytemark/webdav` service (Basic auth,
self-signed TLS) to a running KTD instance, for real end-to-end testing
of this plugin's transport (rather than the public test WebDAV servers
that exist on the internet, which are third-party services not
appropriate to build a repeatable test plan around).

Bring it up alongside a KTD instance that also has this plugin mounted:

\`\`\`bash
ktd --name bug_43666 --single-plugin "$(pwd)" -f "$(pwd)/compose/webdav.yml" up -d
\`\`\`

Reachable from the `koha` container at `https://webdav:443/` (compose
service-name DNS) and from the host at `https://localhost:8443/` for
manual `curl`/browser sanity checks. Credentials: `koha`/`koha`.

Because the cert is self-signed, a `file_transports` row pointed at this
container needs its `debug` flag on (see `Koha::Plugin::Com::OpenFifth::
File::Transport::WebDAV::_ua`) to skip TLS verification - this is a
test-only convenience, not a recommendation for production WebDAV
endpoints, which should use a properly-signed certificate and leave
`debug` off.
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: add KTD compose fragment for a real WebDAV test server"
```

---

### Task 5: Documentation, KTD integration, and final verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: a fully documented, installed, and automated-test-green plugin inside the `bug_43666` KTD instance, with the WebDAV test container running alongside it — ready for the manual librarian end-to-end walkthrough (not part of this plan).

- [ ] **Step 1: Rewrite `README.md`**

Replace the template's generic content (from "Prerequisites" onward — keep the "Koha Plugin Auto Release Template" boilerplate about version/release scripts, since that machinery is unchanged) with a top section describing the plugin itself:

```markdown
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
```

Keep everything from the template's "## Features" heading onward unchanged, except updating the `git clone`-adjacent example JSON under "Setup" step 3 to match this plugin's real `package.json` values (module `Koha::Plugin::Com::OpenFifth::FileTransportWebDAV`, pm_path `Koha/Plugin/Com/OpenFifth/FileTransportWebDAV.pm`).

- [ ] **Step 2: Update `CHANGELOG.md`**

Edit the `[Unreleased]` section's `### Added` heading:

```markdown
### Added

- WebDAV file transport backend (`Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV`), registered against `Koha::File::Transports` via bug 43666's pluggable Single Table Inheritance mechanism.
```

Also replace the placeholder repository URL at the bottom of the file:

```markdown
[Unreleased]: https://github.com/openfifth/koha-plugin-file-transport-webdav/compare/v0.0.0...HEAD
```

(Adjust the org/repo name here if the actual GitHub repo, once created, uses a different path — this plan doesn't create or push to a remote; see the plan's closing note.)

- [ ] **Step 3: Write `CLAUDE.md`**

Create `CLAUDE.md`, following the structure of the sibling `koha-plugin-crontab/CLAUDE.md`:

```markdown
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
```

- [ ] **Step 4: Commit the documentation**

```bash
git add -A
git commit -m "docs: document the plugin, WebDAV conventions, and promotion path"
```

- [ ] **Step 5: Bring up the `bug_43666` KTD instance with this plugin mounted**

The `bug_43666` KTD instance is already running without plugin support
enabled. Bring it down and back up with `--single-plugin` (so only this
plugin, not every sibling repo under `~/Projects/koha/plugins/`, is
exposed) and the WebDAV test service from Task 4:

```bash
cd /home/martin/Projects/koha/core/worktrees/bug_43666
ktd --name bug_43666 down
ktd --name bug_43666 --single-plugin "/home/martin/Projects/koha/plugins/koha-plugin-file-transport-webdav" \
    -f "/home/martin/Projects/koha/plugins/koha-plugin-file-transport-webdav/compose/webdav.yml" up -d
ktd --name bug_43666 --wait-ready 240
```

- [ ] **Step 6: Verify the network name assumption from Task 4 Step 1**

```bash
docker network ls | grep kohanet
```

If the actual network name doesn't match `compose/webdav.yml`'s
`name:` value, fix that file and re-run Step 5's `up -d`, then re-commit.

- [ ] **Step 7: Install the plugin and run its automated test suite inside KTD**

```bash
ktd --name bug_43666 --shell --run 'cd /kohadevbox/koha && perl misc/devel/install_plugins.pl'
ktd --name bug_43666 --shell --run '
    cd /kohadevbox/plugins/koha-plugin-file-transport-webdav &&
    export KOHA_PLUGIN_DIR=$(pwd) &&
    export PERL5LIB=$PERL5LIB:. &&
    prove -v -r t/
'
```

Expected: both commands succeed, and `prove`'s final summary shows all
of `t/00-load.t` and `t/Transport/WebDAV.t` passing.

- [ ] **Step 8: Confirm the plugin is discoverable for STI registration**

```bash
ktd --name bug_43666 --shell --run "cd /kohadevbox/koha && perl -MKoha::Plugins -e '
    my \@plugins = Koha::Plugins->new->GetPlugins({ method => \"additional_sti_classes\" });
    print scalar(\@plugins), \" plugin(s) implementing additional_sti_classes\n\";
    print ref(\$_), \"\n\" for \@plugins;
'"
```

Expected output includes exactly one line:
`Koha::Plugin::Com::OpenFifth::FileTransportWebDAV`

- [ ] **Step 9: Confirm the WebDAV test container is reachable from the koha container**

```bash
ktd --name bug_43666 --shell --run 'curl -s -k -u koha:koha -X PROPFIND -H "Depth: 0" https://webdav:443/ -o /dev/null -w "%{http_code}\n"'
```

Expected: `207`

- [ ] **Step 10: Commit any fixes made in Steps 6-9**

If any step above required a fix (network name, a `_list_files` parsing
edge case against the container's actual PROPFIND response shape,
etc.), commit those fixes now with a message describing what was wrong
and why:

```bash
git add -A
git commit -m "fix: <describe what Steps 6-9 uncovered>"
```

If nothing needed fixing, skip this step - there's nothing to commit.

---

## Plan complete

At this point: the plugin installs cleanly, its automated test suite
passes inside a real KTD instance, it's discoverable via
`GetPlugins({ method => 'additional_sti_classes' })`, and a real WebDAV
server is running alongside it and reachable from the `koha` container.
This is everything bug 43666's own librarian-facing test plan needs to
proceed - that manual walkthrough (kill-switch on, plugin permission
toggle, creating a real `transport='webdav'` row, listing/uploading/
downloading/renaming a file, toggling off and confirming fallback) is
deliberately not a task in this plan; it happens next, using what this
plan built.
