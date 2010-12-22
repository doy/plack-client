#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::TCP;

use Plack::Client;

test_tcp(
    client => sub {
        my $port = shift;

        my $client = Plack::Client->new;
        isa_ok($client, 'Plack::Client');

        {
            my $res = $client->get('http://localhost:5000/');
            isa_ok($res, 'Plack::Response');
            is($res->status, 200, "right status");
            is_deeply($res->headers, ["Content-Type" => "text/plain"],
                    "right headers");
            is($res->body, '/', "right body");
        }

        {
            my $res = $client->get('http://localhost:5000/foo');
            isa_ok($res, 'Plack::Response');
            is($res->status, 200, "right status");
            is_deeply($res->headers, ["Content-Type" => "text/plain"],
                    "right headers");
            is($res->body, '/foo', "right body");
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
        is_deeply($res->headers, ["Content-Type" => "text/plain"],
                  "right headers");
        is($res->body, '/', "right body");
    }

    {
        my $res = $client->get('psgi://foo/foo');
        isa_ok($res, 'Plack::Response');
        is($res->status, 200, "right status");
        is_deeply($res->headers, ["Content-Type" => "text/plain"],
                  "right headers");
        is($res->body, 'oof/', "right body");
    }
}

done_testing;
