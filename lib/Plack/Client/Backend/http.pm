package Plack::Client::Backend::http;
use strict;
use warnings;

use Plack::App::Proxy;

sub new {
    my $class = shift;
    my %params = @_;

    bless {
        proxy => Plack::App::Proxy->new->to_app,
    }, $class;
}

sub proxy { shift->{proxy} }

sub app_from_request {
    my $self = shift;
    my ($req) = @_;

    my $uri = $req->uri->clone;
    $uri->path('/');
    $req->env->{'plack.proxy.remote'} = $uri->as_string;
    return $self->proxy;
}

1;
