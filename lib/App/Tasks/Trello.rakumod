use v6.c;

#
# Copyright © 2023 Joelle Maslak
# All Rights Reserved - See License
#

use URI::Encode;
use Cro::HTTP::Client;
use JSON::Fast;

unit class App::Tasks::Trello:ver<0.2.1>:auth<zef:jmaslak>;

has Str:D $.api-key  is required is rw;
has Str:D $.token    is required is rw;
has Str:D $.base-url             is rw = "https://trello.com/";

method uri-key()   { "key={uri_encode_component($!api-key)}" }
method uri-token() { "token={uri_encode_component($!token)}" }
method me()        { "members/me"                            }

method get_boards() {
    my $url = "/1/{self.me}/boards?{self.uri-key}&{self.uri-token}";
    my $client = Cro::HTTP::Client.new(base-uri => $.base-url);
    my $resp = await $client.get($url);
    my $json = await $resp.body;

    return $json;
}

