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
    my $req = blessed($_[0]) && $_[0]->isa('HTTP::Request')
                  ? $_[0]
                  : HTTP::Request->new(@_);

    my $scheme = $req->uri->scheme;
    my $res;
    if ($scheme eq 'psgi') {
        my ($app_key, $path) = $self->_parse_request($req->uri->opaque);
        my $app = $self->app_for($app_key);
        $req->uri($path); # ?
        die 'XXX' unless $app;
        my $psgi_res = $app->($req->to_psgi);
        die 'XXX' unless ref($psgi_res) eq 'ARRAY';
        $res = Plack::Response->new(@$psgi_res);
    }
    elsif ($scheme eq 'http' || $scheme eq 'https') {
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
