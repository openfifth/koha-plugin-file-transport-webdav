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

our $VERSION         = '0.1.1';
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
