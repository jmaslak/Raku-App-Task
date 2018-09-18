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
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].body.elems, 0, "No notes found";

    $task.task-retitle(1, "New Subject Line");
    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "New Subject Line", "Proper (updated) subject line";
    is @tasks[0].body.elems, 1, "One note found";

    my $expected = "Title changed from:\n  Subject Line\nTo:\n  New Subject Line";
    is @tasks[0].body[0].text, $expected, "Note is correct";

    is $task.LOCKCNT, 0, "Lock count is 0";

    done-testing;
}

tests();

