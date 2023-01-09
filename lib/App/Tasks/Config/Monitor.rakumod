use v6.c;

#
# Copyright © 2018-2023 Joelle Maslak
# All Rights Reserved - See License
#

class App::Tasks::Config::Monitor:ver<0.2.0>:auth<zef:jmaslak> is export {

    has Bool:D $.display-time is rw = True;

    method process-config(%config) {
        if %config<monitor><display-time>:exists {
            $.display-time = %config<monitor><display-time>;
        } else {
            $.display-time = True;
        }
    }
};

=begin POD

=head1 NAME

C<App::Tasks::Config::Monitor> - Monitor Configuration for App::Tasks

=head1 SYNOPSIS

  my $monitor = App::Tasks::Config::Monitor.new()
  $monitor.process-config(%config)
  say "We will display time" if $monitor.display-time;

=head1 DESCRIPTION

This handles the "monitor" command configuration for C<App::Tasks>.  Note
that this module is intended to be instantiated only via C<App::Tasks::Config>.

=head1 FILE FORMAT

  monitor:
   display-time: Yes

This module will parse the C<monitor> section of the configuration YAML file.

=head1 CLASS METHODS

=head2 process-config

  my $monitor = App::Tasks::Config::Monitor.new();
  $monitor->process-config(%config);

This method takes a hash which represents the parsed YAML configuration file.
It will process the C<montitor> section of that configuration file.


=head1 ATTRIBUTES

=head2 display-time

If true, time should be displayed by the C<task monitor> command.

=head1 AUTHOR

Joelle Maslak C<<jmaslak@antelope.net>>

=head1 LEGAL

Licensed under the same terms as Perl 6.

Copyright © 2018-2023 by Joelle Maslak

=end POD

