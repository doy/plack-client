package Plack::Client::Backend::psgi_local;
use strict;
use warnings;
# ABSTRACT: backend for handling local app requests

use Carp;
use Plack::Middleware::ContentLength;

=head1 SYNOPSIS

  Plack::Client->new(
      'psgi-local' => {
          apps => { myapp => sub { ... } },
      },
  );

  Plack::Client->new(
      'psgi-local' => Plack::Client::Backend::psgi_local->new(
          apps => { myapp => sub { ... } },
      ),
  );

=head1 DESCRIPTION

This backend implements requests made against local PSGI apps.

=cut

=method new

Constructor. Takes a hash of arguments, with these keys being valid:

=over 4

=item apps

A mapping of local app names to PSGI app coderefs.

=back

=cut

sub new {
    my $class = shift;
    my %params = @_;

    croak 'apps must be a hashref'
        if ref($params{apps}) ne 'HASH';

    bless {
        apps => $params{apps},
    }, $class;
}

sub _apps { shift->{apps} }

=method app_for

Returns the PSGI app coderef for the given app name.

=cut

sub app_for {
    my $self = shift;
    my ($for) = @_;
    return $self->_apps->{$for};
}

=method app_from_request

Takes a L<Plack::Request> object, and returns the app corresponding to the app
corresponding to the app name given in the C<authority> section of the given
URL.

=cut

sub app_from_request {
    my $self = shift;
    my ($req) = @_;

    my $app_name;
    if (my $uri = $req->env->{'plack.client.original_uri'}) {
        $app_name = $uri->authority;
    }
    else {
        $app_name = $req->uri->authority;
        $app_name =~ s/(.*):.*/$1/; # in case a port was added at some point
    }

    my $app = $self->app_for($app_name);
    croak "Unknown app: $app_name" unless $app;
    return Plack::Middleware::ContentLength->wrap($app);
}

1;
