#!/usr/bin/env perl
use strict;
use warnings;
use lib 't/lib';
use Test::More;
use Plack::Client::Test;

test_tcp_plackup(
    'sub { [ 200, ["Content-Type" => "text/plain"], [shift->{PATH_INFO}] ] }',
    sub {
        my $base_url = shift;

        my $client = Plack::Client->new;
        isa_ok($client, 'Plack::Client');

        {
            my $res = $client->get($base_url . '/');
            response_is($res, 200, ['Content-Type' => 'text/plain'], '/');
        }

        {
            my $res = $client->get($base_url . '/foo');
            response_is($res, 200, ['Content-Type' => 'text/plain'], '/foo');
        }
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
        my $res = $client->get('psgi-local://foo/');
        response_is($res, 200, ['Content-Type' => 'text/plain'], '/');
    }

    {
        my $res = $client->get('psgi-local://foo/foo');
        response_is($res, 200, ['Content-Type' => 'text/plain'], 'oof/');
    }
}

done_testing;
