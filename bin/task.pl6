#!/usr/bin/env perl6
use v6.c;

#
# Copyright © 2018 Joelle Maslak
# All Rights Reserved - See License
#

use lib $*PROGRAM.parent.add("lib");

use App::Tasks;

sub MAIN(
    +@args,
    Bool                  :$expire-today?,
    Bool                  :$show-immature?,
    Bool                  :$all?,
    Str                   :$maturity-date? where { !$_.defined or try Date.new($_) },
    App::Tasks::Task::Tag :$tag?,
) {
    my $task = App::Tasks.new();
    my Date $md;
    $md = Date.new($maturity-date) if $maturity-date;
    $task.start(
        @args,
        :$expire-today,
        :$show-immature,
        :$all,
        :maturity-date($md),
        :$tag,
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

=head2 CONFIGURATION

Optional, a configuration file can be installed in the user's home directory.
If a file named C<.task.yaml> is located there, it is parsed as described in
the L<App::Tasks::Config> documentation.

=head2 COMMANDS

=head3 No command line options

  task.pl

When C<task.pl> is executed without any options, it enters an interactive
mode.  The author rarely uses this mode, preerring command line options
instead.

=head3 new

  task.pl6 new
  task.pl6 new <title>
  task.pl6 --expire-today new
  task.pl6 --expire-today new <title>
  task.pl6 --maturity-date=2099-12-31 new
  task.pl6 --tag=foo new

Create a new task.  If a title is passed on the command line (as a single
argument, so quotes may be needed if you have a multi-word title), it is
simply created with an empty body.

If a title is not provided, an interactive dialog with the user asks for the
title, and, optionally a more detailed set of notes.

If the C<--expire-today> option is provided, the new task will have an
expiration date of today.  See L<#expire> for more details.  This is not
compatibile with the C<--maturity-date> option.

If the C<--maturity-date> option is provided, this sets the maturity date
for the task.  See L<#set-maturity> for more information.

If the C<--tag> option is provided, this sets a tag on the task.  See
L<#add-tag> for more information.

=head3 list

  task.pl6 list
  task.pl6 list <max-items>
  task.pl6 --show-immature list
  task.pl6 --show-immature list <max-items>
  task.pl6 --all list
  task.pl6 --tag=foo list

Display a list of active tasks.  Normally, only non-immature tasks are shown.
If the C<--show-immature> or the C<--all> option is provided, immature tasks
are also shown.  The C<--all> option additional shows all tasks that have a
frequency that would normally prevent them from being shown today (see
the section on C<set-frequency> for more information.

If the C<--tag> option is provided, this lists only tasks with a matching tag.
See L<#add-tag> for more information.

Normally, tasks that include any tag that is listed in the C<ignore-tags>
section of the config file (if it exists) are not displayed.  However, they
will be displayed if C<--all> is specified or if the C<--tag> option includes
one of the tags associated with the task.

Optionally, an integer specifying the maximum number of items to display can
be provided.

=head3 show

  task.pl6 <task-number>
  task.pl6 show <task-number>

Display a task's details.  This uses the C<less> pager if needed.  All notes
will be displayed with the task.

=head3 monitor

  task.pl6 monitor
  task.pl6 --show-immature monitor
  task.pl6 --all monitor

Displays an updating list of tasks that auto-refreshes.  It displays as many
tasks as will fit on the screen.

The C<--show-immature>, C<--all>, and C<--tag> options function as they do for
C<list>.

=head3 note

  task.pl6 note <task-number>

Adds a note to a task.  The note is appended to the task.  Notes are visible
via the L<#show> command.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 close

  task.pl6 close <task-number>

Closes a task (moves it from the 

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 retitle

  task.pl6 retitle <task-number>

Change the title on a task.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 move

  task.pl6 move <task-number> <new-number>

Moves a task from it's current position to a new position (as seen by the list
command).

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 set-expire

  task.pl6 set-expire <task-number>

Set an expiration date.  This is the last day that the task is considered
valid.  This is used for tasks that don't make sense after a given date.  For
instance, if you add a task to buy a Christmas turkey, if you don't actually
do that task before Christmas, it's likely not relevant after Christmas.  Thus,
you might set an expiration date of December 25th.  At that point, it will
be pruned by the L<#expire> command.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 expire

  task.pl6 expire

This closes any open tasks with an expiration date prior to the current date.
It is suitable to run via crontab daily.

This will automatically execute a C<#coalesce>. Thus task numbers will change
after using this.

You must have done a L<#list> in the current window before you can make notes,
in case the task numbers have changed.

=head3 set-frequency

  task.pl6 set-frequency <task-number>

This sets the "display frequency" of the task.  Tasks with a frequency set
will display only on one day out of C<N> number of days.  The C<N> is the
frequency value, with higher values representing less frequent display of
the task.  So, for instance, a frequency of C<7> would indicate that the task
should only be displayed once per week.

The first day the task will be displayed will be betwen now and C<N-1> days
from now.  It will then display every C<N> days.

The idea is that with a large task list with lots of low priority tasks, it
low priority tasks can be assigned a frequency that causes the normal
C<list> to display only a subset of them, so as to not overwhelm.

=head3 set-maturity

  task.pl6 set-maturity <task-number>

Sets the maturity date. Before the maturity date, a task will not be displayed
with the L<#list> or L<#monitor> commands before the maturity date (unless the
C<--show-immature> option is also provided to the L<#list> or L<#monitor>
commands).

=head3 add-tag

  task.pl6 add-tag <task-number> <tag>

Sets a tag (a string with no whitespace) for a given task number.  Tags can
be used to filter tasks with L<#list>. They are also displayed in task lists.

=head3 remove-tag

  task.pl6 remove-tag <task-number> <tag>

Removes a tag (a string with no whitespace) for a given task number.

=head3 coalesce

  task.pl6 coalesce

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

=head3 --maturity-date=YYYY-MM-DD

Sets the maturity date for the L<#new> command when creating a task.  Not
valid with the C<--expire-today> option.  This will be the first day the
task shows up in basic C<task list> output.

=head1 AUTHOR

Joelle Maslak C<<jmaslak@antelope.net>>

=head1 LEGAL

Licensed under the same terms as Perl 6.

Copyright © 2018 by Joelle Maslak

=end POD
