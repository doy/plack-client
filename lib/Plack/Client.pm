package Plack::Client;
use strict;
use warnings;

use HTTP::Message::PSGI;
use HTTP::Request;
use LWP::UserAgent;
use Plack::Response;
use Scalar::Util qw(blessed);

sub new {
    my $class = shift;
    my %params = @_;

    die 'XXX' if exists($params{apps}) && ref($params{apps}) ne 'HASH';

    bless {
        apps => $params{apps},
        ua   => exists $params{ua} ? $params{ua} : LWP::UserAgent->new,
    }, $class;
}

sub apps { shift->{apps} }
sub ua   { shift->{ua}   }

sub app_for {
    my $self = shift;
    my ($for) = @_;
    return $self->apps->{$for};
}

sub request {
    my $self = shift;
    my $req = blessed($_[0]) && ($_[0]->isa('HTTP::Request')
                              || $_[0]->isa('Plack::Request'))
                  ? $_[0]
                  : ref($_[0]) eq 'HASH'
                      ? Plack::Request->new(@_)
                      : HTTP::Request->new(@_);

    # both Plack::Request and HTTP::Request have a ->uri method
    my $scheme = $req->uri->scheme;
    my $res;
    if ($scheme eq 'psgi') {
        my ($app_key, $path) = $self->_parse_request($req->uri->opaque);

        # to_psgi doesn't like non-http uris
        $req->uri($path);
        my $env = $req->isa('HTTP::Request') ? $req->to_psgi : $req->env;

        my $app = $self->app_for($app_key);
        die 'XXX' unless $app;
        my $psgi_res = $app->($env);
        die 'XXX' unless ref($psgi_res) eq 'ARRAY';
        $res = Plack::Response->new(@$psgi_res);
    }
    elsif ($scheme eq 'http' || $scheme eq 'https') {
        $req = $self->_req_from_psgi($req)
            if $req->isa('Plack::Request');

        my $http_res = $self->ua->simple_request($req); # or just ->request?
        $res = Plack::Response->new(
            map { $http_res->$_ } qw(code headers content)
        );
    }
    else {
        die 'XXX';
    }

    return $res;
}

sub _req_from_psgi {
    my $self = shift;
    my ($req) = @_;
    return HTTP::Request->new(
        map { $req->$_ } qw(method uri headers raw_body)
    );
}

sub _parse_request {
    my $self = shift;
    my ($req) = @_;
    my ($app, $path) = $req =~ m+^//(.*?)(/.*)$+;
    return ($app, $path);
}

sub get    { shift->request('GET',    @_) }
sub head   { shift->request('HEAD',   @_) }
sub post   { shift->request('POST',   @_) }
sub put    { shift->request('PUT',    @_) }
sub delete { shift->request('DELETE', @_) }

1;
