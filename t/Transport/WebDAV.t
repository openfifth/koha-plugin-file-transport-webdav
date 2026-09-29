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
