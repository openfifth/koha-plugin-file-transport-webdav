use Modern::Perl;
use Test::More;
use Test::Exception;
use Test::MockModule;
use Mojo::Message::Response;

my $plugin_dir = $ENV{KOHA_PLUGIN_DIR} || '.';
unshift @INC, $plugin_dir;

use_ok('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');

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

subtest '_url_for' => sub {
    plan tests => 6;

    my $module = Test::MockModule->new('Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV');
    my $obj    = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';

    # Subpath host (Nextcloud-style), trailing slash, no credentials
    $module->mock( host                => sub { 'https://dav.example.com:8443/remote.php/dav/files/testuser/' } );
    $module->mock( port                => sub {8443} );
    $module->mock( user_name           => sub {undef} );
    $module->mock( plain_text_password => sub {undef} );

    is( $obj->_url_for('/dir/file.txt')->to_string,
        'https://dav.example.com:8443/remote.php/dav/files/testuser/dir/file.txt',
        'subpath in host is preserved when building a request URL' );

    is( $obj->_url_for('/')->to_string,
        'https://dav.example.com:8443/remote.php/dav/files/testuser/',
        'root path against a subpath host keeps the subpath without doubling the slash' );

    # Same subpath host without a trailing slash
    $module->mock( host => sub { 'https://dav.example.com:8443/remote.php/dav/files/testuser' } );
    is( $obj->_url_for('/dir/file.txt')->to_string,
        'https://dav.example.com:8443/remote.php/dav/files/testuser/dir/file.txt',
        'subpath in host without a trailing slash is still preserved' );

    # Bare host (no subpath) - regression check, unaffected by the fix
    $module->mock( host => sub {'dav.example.com'} );
    is( $obj->_url_for('/dir/file.txt')->to_string,
        'https://dav.example.com:8443/dir/file.txt',
        'bare host with no subpath is unaffected' );

    # Credentials still attached
    $module->mock( user_name           => sub {'alice'} );
    $module->mock( plain_text_password => sub {'s3cret'} );
    is( $obj->_url_for('/dir')->userinfo, 'alice:s3cret', 'credentials are still attached to the URL' );

    # Subpath and credentials combine correctly. Mojo::URL's to_string()
    # deliberately omits userinfo for safety (so it's fine to log
    # $url->to_string in add_message/_record_error payloads without
    # leaking credentials) - to_unsafe_string() is used here only to
    # assert the credentials really are attached to the URL object that
    # gets sent over the wire (Mojo::Message::Request::fix_headers turns
    # url->userinfo into a Basic Authorization header at request-send
    # time, independently of how the URL is stringified for display).
    $module->mock( host => sub { 'https://dav.example.com:8443/base/' } );
    is( $obj->_url_for('/dir/file.txt')->to_unsafe_string,
        'https://alice:s3cret@dav.example.com:8443/base/dir/file.txt',
        'subpath and credentials combine correctly' );
};

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

# _download_file's remaining behaviour (beyond the GET request shape, which
# is structurally identical to _upload_file's PUT, covered above) is writing
# the response body to a local path via Mojo::Asset's move_to(). A fresh
# Mojo::Message::Response with ->body(...) set gets a real Mojo::Asset::Memory
# under the hood, and move_to() on that is a genuine (not mocked) filesystem
# write - so this is exercised for real here, not stubbed out.
subtest '_download_file request shape' => sub {
    plan tests => 3;

    my $captured_url;
    my $ua_module = Test::MockModule->new('Mojo::UserAgent');
    $ua_module->mock(
        get => sub {
            my ( $self, $url ) = @_;
            $captured_url = "$url";
            my $res = Mojo::Message::Response->new;
            $res->code(200);
            $res->body('downloaded content');
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
    my $local_file = "$tmp";
    close $tmp;

    my $ok = $transport->_download_file( 'report.csv', $local_file );
    ok( $ok, 'download reports success' );
    is( $captured_url, 'https://dav.example.com:443/base/report.csv', 'GET issued against the current path + remote filename' );

    open my $fh, '<', $local_file or die "Cannot open $local_file: $!";
    local $/;
    my $written = <$fh>;
    close $fh;
    is( $written, 'downloaded content', 'response body written to the local file via move_to' );
};

subtest '_response_error' => sub {
    plan tests => 3;

    my $obj = bless {}, 'Koha::Plugin::Com::OpenFifth::File::Transport::WebDAV';

    my $transport_failure = Mojo::Message::Response->new;
    $transport_failure->error( { message => 'Connection refused' } );
    is(
        $obj->_response_error( $transport_failure, 'fallback' ),
        'Connection refused',
        'a real transport-level error (no HTTP response) is preferred over the fallback'
    );

    my $http_failure = Mojo::Message::Response->new;
    $http_failure->code(404);
    $http_failure->message('Not Found');
    is(
        $obj->_response_error( $http_failure, 'fallback' ),
        'Not Found',
        'an HTTP reason phrase is used when there is no transport-level error'
    );

    my $nothing = Mojo::Message::Response->new;
    is(
        $obj->_response_error( $nothing, 'fallback' ),
        'fallback',
        'the fallback literal is used when neither error nor message is available'
    );
};

done_testing();
