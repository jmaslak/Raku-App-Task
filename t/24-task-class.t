use v6.c;
use Test;
use App::Tasks;
use App::Tasks::Task;

use File::Temp;

class MockInFH {
    has @.lines;

    method get(-->Str) {
        return shift @!lines;
    }

    method t(-->Bool) { False }
}

sub tests {
    my $tmpdir = tempdir.IO;    # Get IO::Path object for tmpdir.
    note "# Using directory {$tmpdir.Str}";

    my $task = App::Tasks.new( :data-dir($tmpdir) );

    my @lines = (
        'Subject Line',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new(), "00001", "Added new task";

    my $day = DateTime.now.local.Date.Str;
    $task.task-set-expiration(1, $day);

    my @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0]<header><title>, "Subject Line", "Proper subject line";
    is @tasks[0]<body>.elems, 1, "One note found";
    is @tasks[0]<header><expires>, $day, "Expires header correct";

    my $one = App::Tasks::Task.from-file( $tmpdir, 1 );
    is $one.title,               @tasks[0]<header><title>,       "field matches: title";
    is $one.created.posix,       @tasks[0]<header><created>,     "field matches: created";
    is $one.expires,             @tasks[0]<header><expires>,     "field matches: expires";
    is $one.body.elems,          @tasks[0]<body>.elems,          "body count matches";
    is $one.body[0].date.posix,  @tasks[0]<body>[0]<date>,       "body date matches";
    is $one.body[0].text,        @tasks[0]<body>[0]<body>.chomp, "body text matches";

    my @orig = $tmpdir.add("00001-none.task").lines.sort.list;
    $one.to-file;
    my @new  = $tmpdir.add("00001-none.task").lines.sort.list;
    is-deeply @new, @orig, "to-file works properly";

    is $task.LOCKCNT, 0, "Lock count is 0";

    done-testing;
}

tests();
