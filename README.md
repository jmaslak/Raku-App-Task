[![Build Status](https://travis-ci.org/jmaslak/Raku-App-Task.svg?branch=master)](https://travis-ci.org/jmaslak/Raku-App-Task)

POD
===

NAME
====

`task.pl6` - Perl 6 task management application

SYNOPSIS
========

    task.pl6 new          # Add a new task
    task.pl6 list         # List existing tasks
    task.pl6 <num>        # Show information about a task
    task.pl6 note <num>   # Add notes to a task
    task.pl6 close <num>  # Close a task

DESCRIPTION
===========

This program provides basic to-do list management. The project was initially created by its author, Joelle Maslak, to solve her particular task tracking needs. However, it's likely to be useful to others as well.

CAVEATS
=======

This is not yet production-ready code. It runs, and I believe the bugs are reasonably managable, and it meets the author's current needs. However, it was never written with the intent of meeting anyone else's needs!

This code highly depends upon a terminal capable of interepreting the Xterminal color codes.

Editing notes requires the `nano` editor to be installed. The `less` pager is also used.

The author has not yet documented the main classes used by this program.

That said, suggestions are more then welcome!

GOALS / PHILOSOPHY
==================

The goals for this project, which may be changed by the author when she realizes they get in the way of something more important, are:

  * Maintain data in plain-text format

  * Each task is represented by a unique file

  * Simplicity for basic tasks

  * Somewhat scriptable front-end

  * Work inside a Unix shell account

  * Track pending work on a task (notes)

YOU'RE STILL HERE!
==================

Congrats! Now for the usage!

USAGE
=====

ENVIRONMENT
-----------

### `%ENV<TASKDIR>`

This enviornmental variable determines where the task database (files) reside. Open tasks are in this directory, while closed tasks are moved to the `done/` directory under this directory.

The default, if the environmental variable is not set, is `%ENV<HOME>/.task` if the `HOME` environmental variable is set. If the `HOME` environmental variable is not set, it it will be `.task` under the user's current working directory.

CONFIGURATION
-------------

Optional, a configuration file can be installed in the user's home directory. If a file named `.task.yaml` is located there, it is parsed as described in the [App::Tasks::Config](App::Tasks::Config) documentation.

COMMANDS
--------

### No command line options

    task.pl

When `task.pl` is executed without any options, it enters an interactive mode. The author rarely uses this mode, preerring command line options instead.

### new

    task.pl6 new
    task.pl6 new <title>
    task.pl6 --expire-today new
    task.pl6 --expire-today new <title>
    task.pl6 --maturity-date=2099-12-31 new
    task.pl6 --tag=foo new

Create a new task. If a title is passed on the command line (as a single argument, so quotes may be needed if you have a multi-word title), it is simply created with an empty body.

If a title is not provided, an interactive dialog with the user asks for the title, and, optionally a more detailed set of notes.

If the `--expire-today` option is provided, the new task will have an expiration date of today. See [expire](#expire) for more details. This is not compatibile with the `--maturity-date` option.

If the `--maturity-date` option is provided, this sets the maturity date for the task. See [set-maturity](#set-maturity) for more information.

If the `--tag` option is provided, this sets a tag on the task. See [add-tag](#add-tag) for more information.

### list

    task.pl6 list
    task.pl6 list <max-items>
    task.pl6 --show-immature list
    task.pl6 --show-immature list <max-items>
    task.pl6 --all list
    task.pl6 --tag=foo list

Display a list of active tasks. Normally, only non-immature tasks are shown. If the `--show-immature` or the `--all` option is provided, immature tasks are also shown. The `--all` option additional shows all tasks that have a frequency that would normally prevent them from being shown today (see the section on `set-frequency` for more information.

If the `--tag` option is provided, this lists only tasks with a matching tag. See [add-tag](#add-tag) for more information.

Normally, tasks that include any tag that is listed in the `ignore-tags` section of the config file (if it exists) are not displayed. However, they will be displayed if `--all` is specified or if the `--tag` option includes one of the tags associated with the task.

Optionally, an integer specifying the maximum number of items to display can be provided.

### show

    task.pl6 <task-number>
    task.pl6 show <task-number>

Display a task's details. This uses the `less` pager if needed. All notes will be displayed with the task.

### monitor

    task.pl6 monitor
    task.pl6 --show-immature monitor
    task.pl6 --all monitor

Displays an updating list of tasks that auto-refreshes. It displays as many tasks as will fit on the screen.

The `--show-immature`, `--all`, and `--tag` options function as they do for `list`.

### note

    task.pl6 note <task-number>

Adds a note to a task. The note is appended to the task. Notes are visible via the [show](#show) command.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

### close

    task.pl6 close <task-number>

Closes a task (moves it from the 

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

This will automatically execute a `#coalesce`. Thus task numbers will change after using this.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

### retitle

    task.pl6 retitle <task-number>

Change the title on a task.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

### move

    task.pl6 move <task-number> <new-number>

Moves a task from it's current position to a new position (as seen by the list command).

This will automatically execute a `#coalesce`. Thus task numbers will change after using this.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

### set-expire

    task.pl6 set-expire <task-number>

Set an expiration date. This is the last day that the task is considered valid. This is used for tasks that don't make sense after a given date. For instance, if you add a task to buy a Christmas turkey, if you don't actually do that task before Christmas, it's likely not relevant after Christmas. Thus, you might set an expiration date of December 25th. At that point, it will be pruned by the [expire](#expire) command.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

### expire

    task.pl6 expire

This closes any open tasks with an expiration date prior to the current date. It is suitable to run via crontab daily.

This will automatically execute a `#coalesce`. Thus task numbers will change after using this.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

### set-frequency

    task.pl6 set-frequency <task-number>

This sets the "display frequency" of the task. Tasks with a frequency set will display only on one day out of `N` number of days. The `N` is the frequency value, with higher values representing less frequent display of the task. So, for instance, a frequency of `7` would indicate that the task should only be displayed once per week.

The first day the task will be displayed will be betwen now and `N-1` days from now. It will then display every `N` days.

The idea is that with a large task list with lots of low priority tasks, it low priority tasks can be assigned a frequency that causes the normal `list` to display only a subset of them, so as to not overwhelm.

### set-maturity

    task.pl6 set-maturity <task-number>

Sets the maturity date. Before the maturity date, a task will not be displayed with the [list](#list) or [monitor](#monitor) commands before the maturity date (unless the `--show-immature` option is also provided to the [list](#list) or [monitor](#monitor) commands).

### add-tag

    task.pl6 add-tag <task-number> <tag>

Sets a tag (a string with no whitespace) for a given task number. Tags can be used to filter tasks with [list](#list). They are also displayed in task lists.

### remove-tag

    task.pl6 remove-tag <task-number> <tag>

Removes a tag (a string with no whitespace) for a given task number.

### coalesce

    task.pl6 coalesce

Coalesces task numbers, so that the first task becomes task number 1, and any gaps are filled in, moving tasks as required. This is needed if tasks are deleted outside of the `task.pl6` program.

This will automatically execute a `#coalesce`. Thus task numbers will change after using this.

You must have done a [list](#list) in the current window before you can make notes, in case the task numbers have changed.

OPTIONS
-------

### --expire-today

This option is used along with the [new](#new) command to create a task that will expire today (see the [expire](#expire) option for more details).

### --show-immature

Show all open tasks. Normally, tasks that are "immature" (see the L#<set-maturity> command) are not displayed by the [monitor](#monitor) or [list](#list) commands. This option changes that behavior.

### --maturity-date=YYYY-MM-DD

Sets the maturity date for the [new](#new) command when creating a task. Not valid with the `--expire-today` option. This will be the first day the task shows up in basic `task list` output.

AUTHOR
======

Joelle Maslak `jmaslak@antelope.net`

LEGAL
=====

Licensed under the same terms as Perl 6.

Copyright © 2018 by Joelle Maslak

