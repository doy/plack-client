package Plack::Client;
use strict;
use warnings;

use HTTP::Message::PSGI;
use HTTP::Request;
use Plack::App::Proxy;
use Plack::Middleware::ContentLength;
use Plack::Response;
use Scalar::Util qw(blessed reftype);

sub new {
    my $class = shift;
    my %params = @_;

    die 'XXX' if exists($params{apps}) && ref($params{apps}) ne 'HASH';

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

sub request {
    my $self = shift;

    my ($app, $env) = $self->_parse_request_args(@_);

    my $psgi_res = $self->_resolve_response($app->($env));
    # is there a better place to do this? Plack::App::Proxy already takes care
    # of this (since it's making a real http request)
    $psgi_res->[2] = [] if $env->{REQUEST_METHOD} eq 'HEAD';

    # XXX: or just return the arrayref?
    return Plack::Response->new(@$psgi_res);
}

sub _parse_request_args {
    my $self = shift;

    if (blessed($_[0])) {
        if ($_[0]->isa('HTTP::Request')) {
            return $self->_request_from_http_request(@_);
        }
        elsif ($_[0]->isa('Plack::Request')) {
            return $self->_request_from_plack_request(@_);
        }
        else {
            die 'XXX';
        }
    }
    elsif ((reftype($_[0]) || '') eq 'HASH') {
        return $self->_request_from_env(@_);
    }
    else {
        return $self->_request_from_http_request_args(@_);
    }
}

sub _request_from_http_request {
    my $self = shift;
    my ($http_request) = @_;
    my $env = $self->_http_request_to_env($http_request);
    return $self->_request_from_env($env);
}

sub _request_from_plack_request {
    my $self = shift;
    my ($req) = @_;

    return ($self->_app_from_req($req), $req->env);
}

sub _request_from_env {
    my $self = shift;
    return $self->_request_from_plack_request(Plack::Request->new(@_));
}

sub _request_from_http_request_args {
    my $self = shift;
    return $self->_request_from_http_request(HTTP::Request->new(@_));
}

sub _http_request_to_env {
    my $self = shift;
    my ($req) = @_;

    my $scheme = $req->uri->scheme;
    my $app_name;
    # hack around with this - psgi requires a host and port to exist, and
    # for the scheme to be either http or https
    if ($scheme eq 'psgi-local') {
        $app_name = $req->uri->authority;
        $req->uri->scheme('http');
        $req->uri->host('Plack::Client');
        $req->uri->port(-1);
    }
    elsif ($scheme eq 'psgi-local-ssl') {
        $app_name = $req->uri->authority;
        $req->uri->scheme('https');
        $req->uri->host('Plack::Client');
        $req->uri->port(-1);
    }
    elsif ($scheme ne 'http' && $scheme ne 'https') {
        die 'XXX';
    }

    # work around http::message::psgi bug - see github issue 163 for plack
    if (!$req->uri->path) {
        $req->uri->path('/');
    }

    my $env = $req->to_psgi;

    # work around http::message::psgi bug - see github issue 150 for plack
    $env->{CONTENT_LENGTH} ||= length($req->content);

    $env->{'plack.client.url_scheme'} = $scheme;
    $env->{'plack.client.app_name'}   = $app_name
        if defined $app_name;

    return $env;
}

sub _app_from_req {
    my $self = shift;
    my ($req) = @_;

    my $uri = $req->uri;
    my $scheme = $req->env->{'plack.client.url_scheme'} || $uri->scheme;
    my $app_name = $req->env->{'plack.client.app_name'};

    my $app;
    if ($scheme eq 'psgi-local') {
        if (!defined $app_name) {
            $app_name = $uri->authority;
            $app_name =~ s/(.*):.*/$1/; # in case a port was added at some point
        }
        $app = $self->app_for($app_name);
        $app = Plack::Middleware::ContentLength->wrap($app);
    }
    elsif ($scheme eq 'http' || $scheme eq 'https') {
        my $uri = $uri->clone;
        $uri->path('/');
        $app = Plack::App::Proxy->new(remote => $uri->as_string)->to_app;
    }

    die 'XXX' unless $app;

    return $app;
}

sub _resolve_response {
    my $self = shift;
    my ($psgi_res) = @_;

    if (ref($psgi_res) eq 'CODE') {
        my $body = [];
        $psgi_res->(sub {
            $psgi_res = shift;
            return Plack::Util::inline_object(
                write => sub { push @$body, $_[0] },
                close => sub { push @$psgi_res, $body },
            );
        });
    }

    use Data::Dumper; die Dumper($psgi_res) unless ref($psgi_res) eq 'ARRAY';

    return $psgi_res;
}

sub get    { shift->request('GET',    @_) }
sub head   { shift->request('HEAD',   @_) }
sub post   { shift->request('POST',   @_) }
sub put    { shift->request('PUT',    @_) }
sub delete { shift->request('DELETE', @_) }

1;
