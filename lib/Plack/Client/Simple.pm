package Plack::Client::Simple;
use strict;
use warnings;
# ABSTRACT: abstract interface to a single remote web server or local PSGI app

use Carp;
use Plack::Client;
use Plack::Util;
use Scalar::Util qw(blessed reftype);
use Plack::Client::Backend::psgi_local;
use HTTP::Message::PSGI qw(res_from_psgi);

=head1 SYNOPSIS

  use Plack::Client::Simple;

  $client = Plack::Client::Simple->new( sub { ... } );
  $client = Plack::Client::Simple->new( 'http://example.org/' );,
  $client = Plack::Client::Simple->new( $filename_of_psgi_script );

  # get PSGI response
  $res = $client->get('/foo');
  $res = $client->post('/', ['Content-Type' => 'text/plain'], "content");

  # get HTTP::Response
  $client = Plack::Client::Simple->new( $app, as => 'res' );
  $res = $client->get('/foo');

=head1 DESCRIPTION

Plack::Client::Simple uses L<Plack::Client> to wrap PSGI applications and
remote web servers with a common request API borrowed from L<LWP::UserAgent>.

=cut

=method new ( $app | $url )

The constructor creates a client that either wraps a PSGI application, given as
code reference, as filename of a local PSGI script, or as remote web application,
given with its base URL. 

=cut

sub new {
    my ($class, $app, %config) = @_;

    my %backend;
    my $baseurl;

    if (defined $app and !ref $app) {
        if ($app =~ /^https?:/) {
            $backend{http} = { };
            $baseurl = $app;
            $baseurl =~ s{/$}{};
        } elsif ( -f $app ) {
            $app = Plack::Util::load_psgi($app);
        }
    }

    unless ($baseurl) {
        if( ref $app and reftype $app eq 'CODE' ) {
            $backend{'psgi-local'} = Plack::Client::Backend::psgi_local->new(
                apps => { myapp => $app }
            );
            $baseurl = 'psgi-local://myapp';
        } else {
            croak "PSGI application must be a coderef, an URL, or a filename";
        }
    }

    $config{as} //= 'psgi';
    if ($config{as} !~ /^(psgi|res)$/) {
        croak "option 'as' must be 'psgi' or 'res'";
    }

    bless {
        baseurl => $baseurl,
        client  => Plack::Client->new( %backend ),
        as      => $config{as},
    }, $class;
}

=method request ( $method, $url [, $header [, $content ] ] )

  $client->request( GET => '/' );

Dispatch a HTTP request to the PSGI app or to the remote app.
Returns a PSGI response.

=cut

sub request {
    my $self   = shift;
    my $method = shift;
    my $url    = shift;

    $url = $self->{baseurl} . $url;

    my $res = $self->{client}->request($method, $url, @_);
    $res = $res->finalize if blessed $res;

    $res = res_from_psgi($res) if $self->{as} eq 'res';
    return $res;
}

=method get

=method head

=method post

=method put

=method delete

  $client->get('/foo');
  $client->head('/admin');
  $client->post('/submit', [], "my submission");
  $client->put('/new-item', [], "something new");
  $client->delete('/item/2');

These methods are used to dispatch requests given in the same form as requests
methods of L<Plack::Client> and L<LWP::UserAgent> but with abbreviated URL.

=cut

sub get    { shift->request('GET',    @_) }
sub head   { shift->request('HEAD',   @_) }
sub post   { shift->request('POST',   @_) }
sub put    { shift->request('PUT',    @_) }
sub delete { shift->request('DELETE', @_) }

1;
