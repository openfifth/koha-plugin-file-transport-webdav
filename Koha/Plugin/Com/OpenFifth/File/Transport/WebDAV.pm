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
