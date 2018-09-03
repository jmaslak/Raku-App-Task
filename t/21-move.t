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

    @lines = (
        'Second Task',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new(), "00002", "Added new task";

    my @tasks = $task.read-tasks;
    is @tasks.elems, 2, "Proper number of tasks exist (A)";
    is @tasks[0]<header><title>, "Subject Line", "Proper subject line (1)";
    is @tasks[1]<header><title>, "Second Task", "Proper subject line (2)";
    is @tasks[0]<number>, 1, "Proper number (A1)";
    is @tasks[1]<number>, 2, "Proper Number (A2)";

    $task.task-move(2, 1);
    @tasks = $task.read-tasks;
    is @tasks.elems, 2, "Proper number of tasks exist (B)";
    is @tasks[0]<header><title>, "Second Task", "Proper subject line (3)";
    is @tasks[1]<header><title>, "Subject Line", "Proper subject line (4)";
    is @tasks[0]<number>, 1, "Proper number (B1)";
    is @tasks[1]<number>, 2, "Proper Number (B2)";

    $task.task-move(1, 2);
    @tasks = $task.read-tasks;
    is @tasks.elems, 2, "Proper number of tasks exist (C)";
    is @tasks[0]<header><title>, "Subject Line", "Proper subject line (5)";
    is @tasks[1]<header><title>, "Second Task", "Proper subject line (6)";
    is @tasks[0]<number>, 1, "Proper number (C1)";
    is @tasks[1]<number>, 2, "Proper Number (C2)";

    is $task.LOCKCNT, 0, "Lock count is 0";

    done-testing;
}

tests();

