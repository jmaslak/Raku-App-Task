#!/usr/bin/env perl6
use v6;

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

use lib $*PROGRAM.parent.add("lib");

use App::Tasks;

sub MAIN(+@args, Bool :$expire-today?, Bool :$show-immature?) {
    my $task = App::Tasks.new();
    $task.start(
        @args,
        :$expire-today,
        :$show-immature,
    );
}

=begin POD

=head1 NAME

C<task.pl6> - Perl 6 task management application

=head1 SYNOPSIS

  task.pl6 new          # Add a new task
  task.pl6 list         # List existing tasks
  task.pl6 <num>        # Show information about a task
  task.pl6 note <num>   # Add notes to a task
  task.pl6 close <num>  # Close a task

=head1 DESCRIPTION

This program provides basic to-do list management.  The project was initially
created by its author, Joelle Maslak, to solve her particular task tracking
needs.  However, it's likely to be useful to others as well.

=head1 CAVEATS

This is not yet production-ready code. It runs, and I believe the bugs are
reasonably managable, and it meets the author's current needs.  However, it
was never written with the intent of meeting anyone else's needs!

This code highly depends upon a terminal capable of interepreting the Xterminal
color codes.

Editing notes requires the C<nano> editor to be installed.  The C<less> pager
is also used.

The author has not yet documented the main classes used by this program.

That said, suggestions are more then welcome!

=head1 GOALS / PHILOSOPHY

The goals for this project, which may be changed by the author when she
realizes they get in the way of something more important, are:

=item Maintain data in plain-text format
=item Each task is represented by a unique file
=item Simplicity for basic tasks
=item Somewhat scriptable front-end
=item Work inside a Unix shell account
=item Track pending work on a task (notes)

=head1 YOU'RE STILL HERE!

Congrats! Now for the usage!

=head1 USAGE

=head2 ENVIRONMENT

=head3 C<%ENV<TASKDIR>>

This enviornmental variable determines where the task database (files)
reside.  Open tasks are in this directory, while closed tasks are moved
to the C<done/> directory under this directory.

The default, if the environmental variable is not set, is C<%ENV<HOME>/.task>
if the C<HOME> environmental variable is set.  If the C<HOME> environmental
variable is not set, it it will be C<.task> under the user's current working
directory.

=head2 COMMANDS

=head3 No command line options

  task.pl

When C<task.pl> is executed without any options, it enters an interactive
mode.  The author rarely uses this mode, preerring command line options
instead.

=head3 new

  task.pl new
  task.pl new <title>
  task.pl --expire-today new
  task.pl --expire-today new <title>

Create a new task.  If a title is passed on the command line (as a single
argument, so quotes may be needed if you have a multi-word title), it is
simply created with an empty body.

If a title is not provided, an interactive dialog with the user asks for the
title, and, optionally a more detailed set of notes.

If the C<--expire-today> option is provided, the new task will have an
expiration date of today.  See L<#expire> for more details.

=head3 list

  task.pl list
  task.pl list <max-items>
  task.pl --show-immature list
  task.pl --show-immature list <max-items>

Display a list of active tasks.  Normally, only non-immature tasks are shown.
If the C<--show-immature> option is provided, immature tasks are also shown.

Optionally, an integer specifying the maximum number of items to display can
be provided.

=head3 show

  task.pl <task-number>
  task.pl show <task-number>

Display a task's details.  This uses the C<less> pager if needed.  All notes
will be displayed with the task.

=head3 monitor

  task.pl monitor
  task.pl --show-immature monitor

Displays an updating list of tasks that auto-refreshes.  It displays as many
tasks as will fit on the screen.

=head3 note

  task.pl note <task-number>

Adds a note to a task.  The note is appended to the task.  Notes are visible
via the L<#show> command.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 close

  task.pl close <task-number>

Closes a task (moves it from the 

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 retitle

  task.pl retitle <task-number>

Change the title on a task.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 move

  task.pl move <task-number> <new-number>

Moves a task from it's current position to a new position (as seen by the list
command).

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 set-expire

  task.pl set-expire <task-number>

Set an expiration date.  This is the last day that the task is considered
valid.  This is used for tasks that don't make sense after a given date.  For
instance, if you add a task to buy a Christmas turkey, if you don't actually
do that task before Christmas, it's likely not relevant after Christmas.  Thus,
you might set an expiration date of December 25th.  At that point, it will
be pruned by the L<#expire> command.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 expire

  task.pl expire

This closes any open tasks with an expiration date prior to the current date.
It is suitable to run via crontab daily.

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 set-maturity

  task.pl set-maturity <task-number>

Sets the maturity date. Before the maturity date, a task will not be displayed
with the L<#list> or L<#monitor> commands before the maturity date (unless the
C<--show-immature> option is also provided to the L<#list> or L<#monitor>
commands).

=head3 coalesce

  task.pl coalesce

Coalesces task numbers, so that the first task becomes task number 1, and any
gaps are filled in, moving tasks as required.  This is needed if tasks are
deleted outside of the C<task.pl6> program.

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head2 OPTIONS

=head3 --expire-today

This option is used along with the L<#new> command to create a task that will
expire today (see the L<#expire> option for more details).

=head3 --show-immature

Show all open tasks.  Normally, tasks that are "immature" (see the
L#<set-maturity> command) are not displayed by the L<#monitor> or L<#list>
commands.  This option changes that behavior.

=head1 AUTHOR

Joelle Maslak C<<jmaslak@antelope.net>>

=head1 LEGAL

Licensed under the same terms as Perl 6.

Copyright © 2018 by Joelle Maslak

=end POD
