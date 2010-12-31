package Plack::Client;
use strict;
use warnings;

use HTTP::Message::PSGI;
use HTTP::Request;
use Plack::App::Proxy;
use Plack::Response;
use Scalar::Util qw(blessed);

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
    my $req = blessed($_[0]) && ($_[0]->isa('HTTP::Request')
                              || $_[0]->isa('Plack::Request'))
                  ? $_[0]
                  : ref($_[0]) eq 'HASH'
                      ? Plack::Request->new(@_)
                      : HTTP::Request->new(@_);

    # both Plack::Request and HTTP::Request have a ->uri method
    my $scheme = $req->uri->scheme;
    my $app;
    if ($scheme eq 'psgi-local') {
        $req->uri->path('/') unless length $req->uri->path;
        $app = $self->app_for($req->uri->authority);
    }
    elsif ($scheme eq 'http' || $scheme eq 'https') {
        my $uri = $req->uri->clone;
        $uri->path('/');
        $app = Plack::App::Proxy->new(remote => $uri->as_string)->to_app;
    }

    die 'XXX' unless $app;

    my $env = $req->isa('HTTP::Request') ? $req->to_psgi : $req->env;
    $env->{CONTENT_LENGTH} ||= length($req->content); # XXX: ???
    my $psgi_res = $app->($env);
    if (ref($psgi_res) eq 'CODE') {
        my $body = '';
        $psgi_res->(sub {
            $psgi_res = shift;
            return Plack::Util::inline_object(
                write => sub { $body .= $_[0] },
                close => sub { push @$psgi_res, $body },
            );
        });
    }
    use Data::Dumper; die Dumper($psgi_res) unless ref($psgi_res) eq 'ARRAY';

    # XXX: or just return the arrayref?
    return Plack::Response->new(@$psgi_res);
}

sub _req_from_psgi {
    my $self = shift;
    my ($req) = @_;
    return HTTP::Request->new(
        map { $req->$_ } qw(method uri headers raw_body)
    );
}

sub get    { shift->request('GET',    @_) }
sub head   { shift->request('HEAD',   @_) }
sub post   { shift->request('POST',   @_) }
sub put    { shift->request('PUT',    @_) }
sub delete { shift->request('DELETE', @_) }

1;
