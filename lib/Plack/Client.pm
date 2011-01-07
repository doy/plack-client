package Plack::Client;
use strict;
use warnings;
# ABSTRACT: abstract interface to remote web servers and local PSGI apps

use HTTP::Message::PSGI;
use HTTP::Request;
use Plack::App::Proxy;
use Plack::Middleware::ContentLength;
use Plack::Response;
use Scalar::Util qw(blessed reftype);

=head1 SYNOPSIS

  use Plack::Client;
  my $client = Plack::Client->new({ myapp => sub { ... } });
  my $res1 = $client->get('http://google.com/');
  my $res2 = $client->post(
      'psgi-local://myapp/foo.html',
      ['Content-Type' => 'text/plain'],
      "foo"
  );

=head1 DESCRIPTION

B<NOTE: This is a trial release while I work out what the API should be. Use at your own risk!>

A common task required in more complicated web applications is communicating
with various web services for different tasks. These web services may be spread
among a number of different servers, but some of them may be on the local
server, and for those, there's no reason to require accessing them through the
network; assuming the app is written using Plack, the app coderef for the
service already exists in the current process, so a lot of time could be saved
by just calling it directly.

The key issue here then becomes providing an interface that allows accessing
both local and remote services through a common api, so that services can be
moved between servers with only a small change in configuration, rather than
having to change the actual code involved in accessing it. This module solves
this issue by providing an API similar to L<LWP::UserAgent>, but using an
underlying implementation consisting entirely of Plack apps. Local apps are
distinguished from remote apps by the URL scheme: remote URLs use C<http> or
C<https>, while local URLs use C<psgi-local> or C<psgi-local-ssl>. For
instance, accessing C</foo> on a remote application would look like this:
C<< $client->get('http://some.other.server.com/foo') >>, and accessing the same
thing on a local application would look like this:
C<< $client->get('psgi-local://myapp/foo') >>, but they will both give the same
result. This API allows a simple config file change to be all that's necessary
to migrate your service to a different server.

=cut

=method new

  my $client = Plack::Client->new(
      apps => {
          foo => sub { ... },
          bar => MyApp->new->to_app,
      }
  )

Constructor. Takes a hash of arguments, with these keys being valid:

=over 4

=item apps

A mapping of local app names to PSGI app coderefs. These are the apps that will
be available via the C<psgi-local> URL scheme.

=back

=cut

sub new {
    my $class = shift;
    my %params = @_;

    die 'apps must be a hashref'
        if exists($params{apps}) && ref($params{apps}) ne 'HASH';

    bless {
        apps  => $params{apps},
        proxy => Plack::App::Proxy->new,
    }, $class;
}

=method apps

  my $apps = $client->apps;

Returns the C<apps> hashref that was passed to the constructor.

=cut

sub apps   { shift->{apps}  }
sub _proxy { shift->{proxy} }

=method app_for

  my $app = $client->app_for('foo');

Returns the app corresponding to the given app name (or undef, if no such app
exists).

=cut

sub app_for {
    my $self = shift;
    my ($for) = @_;
    return $self->apps->{$for};
}

=method request

  $client->request(
      'POST',
      'http://example.com/',
      ['Content-Type' => 'text/plain'],
      "content",
  );
  $client->request(HTTP::Request->new(...));
  $client->request($env);
  $client->request(Plack::Request->new(...));

This method performs most of the work for this module. It takes a request in
any of several forms, makes the request, and returns the response as a
L<Plack::Response> object. The request can be in the form of an
L<HTTP::Request> or L<Plack::Request> object directly, or it can take arguments
to pass to the constructor of either of those two modules (so see those two
modules for a description of exactly what is valid).

=cut

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
            die 'Request object must be either an HTTP::Request or a Plack::Request';
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
        die 'Invalid URL scheme ' . $scheme;
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
        die "Unknown app: $app_name" unless $app;
        $app = Plack::Middleware::ContentLength->wrap($app);
    }
    elsif ($scheme eq 'http' || $scheme eq 'https') {
        my $uri = $uri->clone;
        $uri->path('/');
        $req->env->{'plack.proxy.remote'} = $uri->as_string;
        $app = $self->_proxy;
    }

    die "Couldn't find app" unless $app;

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

=method get

=method head

=method post

=method put

=method delete

  $client->get('http://example.com/foo');
  $client->head('psgi-local://bar/admin');
  $client->post('https://example.com/submit', [], "my submission");
  $client->put('psgi-local-ssl://foo/new-item', [], "something new");
  $client->delete('http://example.com/item/2');

These methods are just shorthand for C<request>. They only allow the "URL,
headers, body" API; for anything more complicated, C<request> should be used
directly.

=cut

sub get    { shift->request('GET',    @_) }
sub head   { shift->request('HEAD',   @_) }
sub post   { shift->request('POST',   @_) }
sub put    { shift->request('PUT',    @_) }
sub delete { shift->request('DELETE', @_) }

=head1 BUGS

No known bugs.

Please report any bugs through RT: email
C<bug-plack-client at rt.cpan.org>, or browse to
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Plack-Client>.

=head1 SEE ALSO

L<Plack>

L<HTTP::Request>

=head1 SUPPORT

You can find this documentation for this module with the perldoc command.

    perldoc Plack::Client

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Plack-Client>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Plack-Client>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Plack-Client>

=item * Search CPAN

L<http://search.cpan.org/dist/Plack-Client>

=back

=cut

1;
