use v6.c;
use Test;
use App::Tasks;

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

    my @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0]<header><title>, "Subject Line", "Proper subject line";
    is @tasks[0]<header><expires>:exists, False, "Expires header does not exist";
    is @tasks[0]<body>.elems, 0, "No notes found";


    my $day = Date.today;
    $task.task-set-expiration(1, $day.Str);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0]<header><title>, "Subject Line", "Proper subject line";
    is @tasks[0]<header><expires>, $day.Str, "Expires header correct";
    is @tasks[0]<body>.elems, 1, "One note found";

    my $expected = "Added expiration date: $day\n";
    is @tasks[0]<body>[0]<body>, $expected, "Note is correct";


    $task.task-set-expiration(1, $day.succ.Str);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0]<header><title>, "Subject Line", "Proper subject line";
    is @tasks[0]<header><expires>, $day.succ.Str, "Expires header correct";
    is @tasks[0]<body>.elems, 2, "Two notes found";

    $expected = "Updated expiration date from $day to " ~ $day.succ ~ "\n";
    is @tasks[0]<body>[1]<body>, $expected, "Note is correct";

    is $task.LOCKCNT, 0, "Lock count is 0";


    @lines = (
        '2 Subject Line',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new-expire-today(), "00002", "Added new task";

    $day = Date.today;

    @tasks = $task.read-tasks;
    is @tasks.elems, 2, "Proper number of tasks exist";
    is @tasks[1]<header><title>, "2 Subject Line", "Proper subject line";
    is @tasks[1]<body>.elems, 1, "One note found";

    is @tasks[1]<header><expires>, $day.Str, "Expires header correct";
    is @tasks[1]<body>.elems, 1, "One note found";

    $expected = "Added expiration date: $day\n";
    is @tasks[1]<body>[0]<body>, $expected, "Note is correct";
    
    done-testing;
}

tests();

