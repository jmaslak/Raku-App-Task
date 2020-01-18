use v6.c;

#
# Copyright © 2018 Joelle Maslak
# All Rights Reserved - See License
#

class App::Tasks::Config:ver<0.0.17>:auth<cpan:JMASLAK> {

    use Terminal::ANSIColor;
    use YAMLish;

    has Str     $.body-color                is rw;
    has Str     $.header-alert-color        is rw;
    has Str     $.header-normal-color       is rw;
    has Str     $.header-seperator-color    is rw;
    has Str     $.header-title-color        is rw;
    has Str     $.immature-task-color       is rw;
    has Str     $.not-displayed-today-color is rw;
    has Str     $.prompt-bold-color         is rw;
    has Str     $.prompt-color              is rw;
    has Str     $.prompt-info-color         is rw;
    has Str     $.tag-color                 is rw;
    has Str     $.reset                     is rw;

    has SetHash $.ignore-tags               is rw = SetHash.new;
    has Str     $.pager-command             is rw = 'less -RFX -P%PROMPT% -- %FILENAME%';
    has Str     $.editor-command            is rw = 'nano -r 72 -s ispell +3,1 %FILENAME%';

    method read-config(IO::Path:D $config-file? = $*HOME.add('.task.yaml')) {
        my $contents = '';
        if $config-file.e {
            $contents = $config-file.slurp.chomp;
        }

        return self.from-string($contents);
    }

    method from-string(Str:D $config-contents) {
        my $obj = self.bless;

        my $y = Hash.new;
        if $config-contents ne '' {
            $y = load-yaml($config-contents);
            if $y !~~ Hash {
                die("Config file does not appear to be properly formatted");
            }
        }

        # Set theme colors
        if $y<theme>:exists {
            if $y<theme>.fc eq 'light' {
                $obj.set-color-default-light();
            } elsif $y<theme>.fc eq 'dark' {
                $obj.set-color-default-dark();
            } elsif $y<theme>.fc eq 'no-color' {
                $obj.set-color-default-no-color();
            } else {
                die("Unknown theme type: " ~ $y<theme>);
            }
            $y<theme>:delete;
        } else {
            $obj.set-color-default-dark();
        }

        $obj.body-color                = c($y, 'body-color')                if $y<body-color>:exists;
        $obj.header-alert-color        = c($y, 'header-alert-color')        if $y<header-alert-color>:exists;
        $obj.header-normal-color       = c($y, 'header-normal-color')       if $y<header-normal-color>:exists;
        $obj.header-seperator-color    = c($y, 'header-seperator-color')    if $y<header-seperator-color>:exists;
        $obj.header-title-color        = c($y, 'header-title-color')        if $y<header-title-color>:exists;
        $obj.immature-task-color       = c($y, 'immature-task-color')       if $y<immature-task-color>:exists;
        $obj.not-displayed-today-color = c($y, 'not-displayed-today-color') if $y<not-displayed-today-color>:exists;
        $obj.prompt-bold-color         = c($y, 'prompt-bold-color')         if $y<prompt-bold-color>:exists;
        $obj.prompt-color              = c($y, 'prompt-color')              if $y<prompt-color>:exists;
        $obj.prompt-info-color         = c($y, 'prompt-info-color')         if $y<prompt-info-color>:exists;
        $obj.tag-color                 = c($y, 'tag-color')                 if $y<tag-color>:exists;
        $obj.reset                     = c($y, 'reset')                     if $y<reset>:exists;

        $obj.ignore-tags               = $y<ignore-tags>:delete.SetHash     if $y<ignore-tags>:exists;
        $obj.pager-command             = $y<pager-command>:delete           if $y<pager-command>:exists;
        $obj.editor-command            = $y<editor-command>:delete          if $y<editor-command>:exists;

        if $y.keys.list.elems > 0 {
            die("Unknown configuration keys: " ~ $y.keys);
        }

        return $obj;
    }

    method no-color() {
        return self.from-string("theme: 'no-color'");
    }

    method set-color-default-dark() {
        $!body-color                = c('yellow');
        $!header-alert-color        = c('bold red');
        $!header-normal-color       = c('bold yellow');
        $!header-seperator-color    = c('red');
        $!header-title-color        = c('bold green');
        $!immature-task-color       = c('yellow');
        $!not-displayed-today-color = c('yellow');
        $!prompt-bold-color         = c('bold green');
        $!prompt-color              = c('bold cyan');
        $!prompt-info-color         = c('cyan');
        $!tag-color                 = c('red');
        $!reset                     = c('reset');
    }

    method set-color-default-light() {
        $!body-color                = c('94');
        $!header-alert-color        = c('red');
        $!header-seperator-color    = c('red');
        $!header-title-color        = c('28');
        $!header-normal-color       = c('94');
        $!immature-task-color       = c('yellow');
        $!not-displayed-today-color = c('yellow');
        $!prompt-bold-color         = c('green');
        $!prompt-color              = c('cyan');
        $!prompt-info-color         = c('cyan');
        $!tag-color                 = c('28');
        $!reset                     = c('reset');
    }

    method set-color-default-no-color() {
        $!body-color                = '';
        $!header-alert-color        = '';
        $!header-title-color        = '';
        $!header-seperator-color    = '';
        $!header-normal-color       = '';
        $!immature-task-color       = '';
        $!not-displayed-today-color = '';
        $!prompt-bold-color         = '';
        $!prompt-color              = '';
        $!prompt-info-color         = '';
        $!tag-color                 = '';
        $!reset                     = '';
    }

    #
    # These two multis (c()) colorize a string or, if passed a hash &
    # key, colorize the hash value pointed at by the key and then delete
    # the hash element.
    #
    my multi sub c(Str:D $color-info -->Str:D) {
        # Right now, we just pass the string to color() from Terminal::ANSIColor
        if $color-info ~~ /\W reset \W/ {
            return color($color-info);
        } else {
            return color("reset $color-info");
        }
    }

    my multi sub c(Hash:D $hash, Str:D $key -->Str:D) {
        my $color = c($hash{$key});
        $hash{$key}:delete;

        return $color;
    }

};

=begin POD

=head1 NAME

C<App::Tasks::Config> - Configuration File for App::Tasks

=head1 SYNOPSIS

  my $config = App::Tasks::Config.read-config();
  say $config.reset ~ $config.header-alert-color ~ "ALERT!" ~ $config.reset;

=head1 DESCRIPTION

This file allows configuration of the C<App::Tasks> program via a YAML config
file.

=head1 FILE FORMAT

  theme: dark
  immature-task-color: 'bold red'
  editor-command: 'nano +3,1 %FILENAME%'

First, if a C<theme> key is present, that is used to determine the default
colors (named the same as the class's attributres).  For the config file,
the value of the colors must be valid for the C<Terminal::ANSIColor> module's
C<color> sub.

Valid themes are C<dark>, C<light>, and C<no-color> (you must put quotes
around "no-color" in the YAML file).  The C<dark> theme is suitable for
people using a dark terminal background.  The C<light> theme is suitable for
a light colored terminal background.  The C<no-color> theme disables the ANSI
color codes in all output.

In addition to color configuration, the pager and editor commands may be
specified with this configuration file.

=head1 CLASS METHODS

=head2 read-config

  my $config = App::Tasks::Config.read-config($io-path);

This method optionally takes an C<IO::Path> argument providing the location of
the config file.  If the config file is readable (using the C<.r> method on
the argument), it is parsed as a YAML file for the attributes listed below.

If an IO::Path object is not passed to this method, the config file should be
named C<$*HOME/.task.yaml>, where C<$*HOME> is of course your user home
directory.

=head2 from-string

  my $config = App::Tasks::Config.from-file($config-text);

This method takes a string and parses it as YAML, for the attributes listed
below.

=head2 no-color

  my $config = App::Tasks::Config.no-color;

This is intended primarily for testing.  It will return a configuration object
representing a "no color" output and will not read any config files file.

=head1 COLOR ATTRIBUTES

=head2 body-color

This is the escape codes for the body text.

=head2 header-alert-color 

This is the escape codes for the header alert text (values of headers that
are displayed as "alerts", such as maturity dates that are in the future).

=head2 header-seperator-color

This is the escape codes for the header seperator character (the colon that
appears between the header item title and the header item text).

=head2 header-title-color

This is the escape codes for the header title text.

=head2 header-normal-color

This is the escape codes for the header normal text.

=head2 immature-task-color

This is the escape codes for immature tasks in the main task list (when
display of either all tasks or immature tasks is enabled).

=head2 not-displayed-today-coloor

This is the escape codes for tasks that have a frequency that would normally
prevent them from being displayed in the main task list (only applicable when
display of all tasks is enabled).

=head2 prompt-bold-color

This is the escape codes for bold text in the user prompt.

=head2 prompt-color

This is the escape codes for the non-bolded text in the user prompts.

=head2 prompt-info-color

This is the escape codes for informational text in the user prompts.

=head2 tag-color

This is the escape codes for tags text in task listings.

=head2 reset

This is the escape code to reset text attributes.

=head1 OTHER ATTRIBUTES

=head1 ignore-tags

This is a SetHash containing tags that are, by default, ignored by the C<list>
and C<monitor> commands.  It is specified in the YAML file as follows:

  ignore-tags:
   - abc
   - def

The above YAML snippet wll define abc and def as "ignored tags".

=head1 editor-command

This is the command used as for editing and creating task notes.  An occurance
of C<%FILENAME%> is replaced with a temporary file name (representing the note
to create).

The default value is:

  nano -r 72 -s ispell +3,1 %FILENAME%

This uses the nano editor, with line wrapping at 72 columns.  It uses ispell
as the spell checker.  It positions the cursor at the 3rd line, first column
position.

=head1 pager-command

This is used to display all output that may span more than one page.

Any instance of C<%FILENAME%> is replaced by the temporary file to display.
Any instance of C<%PROMPT%> is replaced by a propt to provide the user to
scroll to the next page.

The default value is:

  less -RFX -P%PROMPT% -- %FILENAME%

=head1 AUTHOR

Joelle Maslak C<<jmaslak@antelope.net>>

=head1 LEGAL

Licensed under the same terms as Perl 6.

Copyright © 2018 by Joelle Maslak

=end POD

