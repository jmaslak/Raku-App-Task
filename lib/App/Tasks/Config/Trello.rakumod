use v6.c;

#
# Copyright © 2018-2023 Joelle Maslak
# All Rights Reserved - See License
#

class App::Tasks::Config::Trello:ver<0.2.1>:auth<zef:jmaslak> is export {

    has Str $.api-key is rw;
    has Str $.token   is rw;

    method process-config(%config) {
        if %config<trello><api-key>:exists {
            $.api-key = %config<trello><api-key>;
            %config<trello><api-key>:delete;
        }
        if %config<trello><token>:exists {
            $.token = %config<trello><token>;
            %config<trello><token>:delete;
        }

        if %config<trello>.keys.list.elems > 0 {
            die("Unknown configuration keys: trello÷" ~ %config<trello>.keys);
        }
    }
};

=begin POD

=head1 NAME

C<App::Tasks::Config::Trello> - Trello Configuration for App::Tasks

=head1 SYNOPSIS

  my $trello = App::Tasks::Config::Trello.new()
  $trello.process-config(%config)
  say "API Key: " ~ $trello.api-key;

=head1 DESCRIPTION

This handles the Trello API configuration for C<App::Tasks>.  Note that this
module is intended to be instantiated only via C<App::Tasks::Config>.

=head1 FILE FORMAT

 trello: 
   api-key: "0123456789abcdef"
   token: "fedcba9876543210"

This module will parse the C<trello> section of the configuration YAML file.

=head1 CLASS METHODS

=head2 process-config

  my $trello = App::Tasks::Config::Trello.new();
  $trello>process-config(%config);

This method takes a hash which represents the parsed YAML configuration file.
It will process the C<trello> section of that configuration file.


=head1 ATTRIBUTES

=head2 api-key

The value, if set, of the API key used to connect to Trello.

=head2 token

The value, if set, of the token used to connect to Trello.

=head1 AUTHOR

Joelle Maslak C<<jmaslak@antelope.net>>

=head1 LEGAL

Licensed under the same terms as Perl 6.

Copyright © 2018-2023 by Joelle Maslak

=end POD

