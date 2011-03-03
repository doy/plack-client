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

Constructor. Takes two optional arguments:

=over 4

=item proxy_args

Hashref of arguments to pass to the L<Plack::App::Proxy> constructor.

=item proxy

L<Plack::App::Proxy> object to use for requests.

=back

=cut

sub new {
    my $class = shift;
    my %args = @_;

    $args{proxy} ||= Plack::App::Proxy->new(
        exists $args{proxy_args} ? $args{proxy_args} : ()
    );

    my $self = $class->SUPER::new(@_);

    $self->{proxy} = $args{proxy}->to_app;

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
    $uri->query(undef);
    $req->env->{'plack.proxy.remote'} = $uri->as_string;
    return $self->_proxy;
}

1;
