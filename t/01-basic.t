#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::TCP;

use Plack::Util;

use Plack::Client;

sub full_body {
    my ($body) = @_;

    return $body unless ref($body);

    my $ret = '';
    Plack::Util::foreach($body, sub { $ret .= $_[0] });
    return $ret;
}

sub check_headers {
    my ($got, $expected) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    isa_ok($got, 'HTTP::Headers');

    if (ref($expected) eq 'ARRAY') {
        $expected = HTTP::Headers->new(@$expected);
    }
    elsif (ref($expected) eq 'HASH') {
        $expected = HTTP::Headers->new(%$expected);
    }
    isa_ok($expected, 'HTTP::Headers');

    my @expected_keys = $expected->header_field_names;
    my @got_keys = $got->header_field_names;

    my %default_headers = map { $_ => 1 } qw(
        Date Server Content-Length Client-Date Client-Peer Client-Response-Num
    );
    my %expected_exists = map { $_ => 1 } @expected_keys;

    for my $header (@expected_keys) {
        is($got->header($header), $expected->header($header),
           "$header header is the same");
    }

    for my $header (@got_keys) {
        next if $default_headers{$header};
        next if $expected_exists{$header};
        fail("got extra header $header");
    }
}

test_tcp(
    client => sub {
        my $port = shift;

        my $client = Plack::Client->new;
        isa_ok($client, 'Plack::Client');

        my $base_url = 'http://localhost:' . $port;

        {
            my $res = $client->get($base_url . '/');
            isa_ok($res, 'Plack::Response');
            is($res->status, 200, "right status");
            check_headers($res->headers, ["Content-Type" => "text/plain"]);
            is(full_body($res->body), '/', "right body");
        }

        {
            my $res = $client->get($base_url . '/foo');
            isa_ok($res, 'Plack::Response');
            is($res->status, 200, "right status");
            check_headers($res->headers, ["Content-Type" => "text/plain"]);
            is(full_body($res->body), '/foo', "right body");
        }
    },
    server => sub {
        my $port = shift;
        exec('plackup', '--port', $port, '-e', 'sub { [ 200, ["Content-Type" => "text/plain"], [shift->{PATH_INFO}] ] }');
    },
);

{
    my $apps = {
        foo => sub {
            [
                200,
                ["Content-Type" => "text/plain"],
                [scalar reverse shift->{PATH_INFO}]
            ]
        },
    };
    my $client = Plack::Client->new(apps => $apps);
    isa_ok($client, 'Plack::Client');
    is($client->apps, $apps, "got apps back");
    is($client->app_for('foo'), $apps->{foo}, "got the right app");
    is($client->app_for('bar'), undef, "didn't get nonexistent app");

    {
        my $res = $client->get('psgi://foo/');
        isa_ok($res, 'Plack::Response');
        is($res->status, 200, "right status");
        check_headers($res->headers, ["Content-Type" => "text/plain"]);
        is(full_body($res->body), '/', "right body");
    }

    {
        my $res = $client->get('psgi://foo/foo');
        isa_ok($res, 'Plack::Response');
        is($res->status, 200, "right status");
        check_headers($res->headers, ["Content-Type" => "text/plain"]);
        is(full_body($res->body), 'oof/', "right body");
    }
}

done_testing;
