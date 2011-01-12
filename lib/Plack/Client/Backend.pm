package Plack::Client::Backend;
use strict;
use warnings;
# ABSTRACT: turns a Plack::Request into a PSGI app

use Carp;
use Scalar::Util qw(weaken);

use overload '&{}' => sub { shift->as_code(@_) }, fallback => 1;

=head1 SYNOPSIS

  package My::Backend;
  use base 'Plack::Client::Backend';

  sub app_from_request {
      my $self = shift;
      my ($req) = @_;
      return sub { ... }
  }

=head1 DESCRIPTION

This is a base class for L<Plack::Client> backends. These backends are handlers
for a particular URL scheme, and translate a L<Plack::Request> instance into a
PSGI application coderef.

=cut

=method new

Creates a new backend instance. Takes no parameters by default, but may be
overridden in subclasses.

=cut

sub new {
    my $class = shift;
    bless {}, $class;
}

=method app_from_request

This method is called with an argument of a L<Plack::Request> object, and
should return a PSGI application coderef. The Plack::Request object it receives
contains the actual env hash that will be passed to the application, so
backends can modify that too, if they need to.

=cut

sub app_from_request {
    croak "Backends must implement app_from_request";
}

=method as_code

Returns a coderef which will call L</app_from_request> as a method.

=cut

sub as_code {
    my $self = shift;
    return sub { $self->app_from_request(@_) };
}

1;
