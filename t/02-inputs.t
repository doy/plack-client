#!/usr/bin/env perl
use strict;
use warnings;
use lib 't/lib';
use Test::More;
use Plack::Client::Test;

my $app = <<'APP';
sub {
    my $env = shift;
    return [
        200,
        ['Content-Type' => 'text/plain'],
        [
            (map { ($env->{$_} || '') . "\n" }
                 qw(
                    REQUEST_METHOD
                    REQUEST_URI
                    CONTENT_LENGTH
                 )),
            (map { ucfirst(lc) . ': ' . $env->{"HTTP_X_$_"} . "\n" }
                 grep { $_ ne 'FORWARDED_FOR' } grep { s/^HTTP_X_// }
                      keys %$env),
            do {
                my $fh = $env->{'psgi.input'};
                $fh->read(my $body, $env->{CONTENT_LENGTH});
                $body;
            },
        ]
    ];
}
APP

test_tcp_plackup(
    $app,
    sub {
        my $base_uri = shift;

        test_responses($base_uri, Plack::Client->new);
    },
);

{
    my $apps = {
        foo => eval $app,
    };
    my $base_uri = 'psgi-local://foo';

    test_responses($base_uri, Plack::Client->new(apps => $apps));
}

sub test_responses {
    my ($base_uri, $client) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    response_is(
        $client->get($base_uri),
        200,
        ['Content-Type' => 'text/plain'],
        "GET\n/\n\n"
    );

    response_is(
        $client->get($base_uri . '/'),
        200,
        ['Content-Type' => 'text/plain'],
        "GET\n/\n\n"
    );

    response_is(
        $client->get($base_uri . '/foo'),
        200,
        ['Content-Type' => 'text/plain'],
        "GET\n/foo\n\n"
    );

    response_is(
        $client->get($base_uri . '/foo', ['X-Foo' => 'bar']),
        200,
        ['Content-Type' => 'text/plain'],
        "GET\n/foo\n\nFoo: bar\n"
    );

    response_is(
        $client->get($base_uri . '/foo', HTTP::Headers->new('X-Foo' => 'bar')),
        200,
        ['Content-Type' => 'text/plain'],
        "GET\n/foo\n\nFoo: bar\n"
    );

    response_is(
        $client->post($base_uri, [], "foo"),
        200,
        ['Content-Type' => 'text/plain'],
        "POST\n/\n3\nfoo",
    );
}

done_testing;
