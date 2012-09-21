package Plack::Client::Simple;
use strict;
use warnings;
# ABSTRACT: abstract interface to a single remote web server or local PSGI app

use Carp;
use Plack::Client;
use Scalar::Util qw(blessed reftype);
use Plack::Client::Backend::psgi_local;

=head1 SYNOPSIS

  use Plack::Client::Simple;

  $client = Plack::Client::Simple->new( sub { ... } );
  $res = $client->get('/foo');

  $client = Plack::Client::Simple->new( 'http://example.org/' );,
  $res = $client->post('/', ['Content-Type' => 'text/plain'], "content");

=head1 DESCRIPTION

Plack::Client::Simple uses L<Plack::Client> to wrap PSGI applications and
remote web servers with a common request API borrowed from L<LWP::UserAgent>.

=cut

=method new ( $app | $url )

The constructor creates a client that either wraps a PSGI application, given as
code reference, or a remote web application, given with its base URL. 

=cut

sub new {
    my ($class, $app) = @_;

    my %backend;
    my $baseurl;

    if (defined $app and !ref $app) {
        $backend{http} = { };
        $baseurl = $app;
        $baseurl =~ s{/$}{};
    } elsif( ref $app and reftype $app eq 'CODE' ) {
        $backend{'psgi-local'} = Plack::Client::Backend::psgi_local->new(
            apps => { myapp => $app }
        );
        $baseurl = 'psgi-local://myapp';
    } else {
        croak "PSGI application must be a coderef or URL";
    }

    bless {
        baseurl => $baseurl,
        client  => Plack::Client->new( %backend )
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
    
    # convert to PSGI response
    return (blessed $res ? $res->finalize : $res);
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

=head1 KNOWN BUGS

This client does not set C<plack.client.original_uri>, so the request URI will
always start with C<http://[plack::client]:-1/> when accessing local PSGI
applications. A later version may support the following:

  $client = Plack::Client::Simple->new( 'http://example.org/' => sub { ... } );
  
  $res->get('/foo'); # request http://example.org/foo by calling the $app

=cut
