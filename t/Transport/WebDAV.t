use Modern::Perl;
use Test::More;
use Test::Exception;
use Test::MockModule;

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

done_testing();
