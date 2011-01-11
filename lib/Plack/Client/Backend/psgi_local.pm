package Plack::Client::Backend::psgi_local;
use strict;
use warnings;

use Carp;
use Plack::Middleware::ContentLength;

sub new {
    my $class = shift;
    my %params = @_;

    croak 'apps must be a hashref'
        if ref($params{apps}) ne 'HASH';

    bless {
        apps => $params{apps},
    }, $class;
}

sub apps { shift->{apps} }

sub app_for {
    my $self = shift;
    my ($for) = @_;
    return $self->apps->{$for};
}

sub app_from_request {
    my $self = shift;
    my ($req) = @_;

    my $app_name = $req->env->{'plack.client.authority'};
    if (!defined $app_name) {
        $app_name = $req->uri->authority;
        $app_name =~ s/(.*):.*/$1/; # in case a port was added at some point
    }
    my $app = $self->app_for($app_name);
    croak "Unknown app: $app_name" unless $app;
    return Plack::Middleware::ContentLength->wrap($app);
}

1;
