package Plack::Client::Backend::http;
use strict;
use warnings;
# ABSTRACT: backend for handling HTTP requests

use Plack::App::Proxy;

use base 'Plack::Client::Backend';

=head1 SYNOPSIS

  Plack::Client->new(
      'http' => {},
  );

  Plack::Client->new(
      'http' => Plack::Client::Backend::http->new,
  );

=head1 DESCRIPTION

This backend implements HTTP requests. The current implementation uses
L<Plack::App::Proxy> to make the request.

=cut

=method new

Constructor. Takes no arguments.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    $self->{proxy} = Plack::App::Proxy->new->to_app;

    return $self;
}

sub _proxy { shift->{proxy} }

=method app_from_request

Takes a L<Plack::Request> object, and returns an app which will retrieve the
HTTP resource.

=cut

sub app_from_request {
    my $self = shift;
    my ($req) = @_;

    my $uri = $req->uri->clone;
    $uri->path('/');
    $req->env->{'plack.proxy.remote'} = $uri->as_string;
    return $self->_proxy;
}

1;
