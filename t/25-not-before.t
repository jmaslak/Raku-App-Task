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
    is $task.task-new(), 1, "Added new task";

    my @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].not-before.defined, False, "Not-before header does not exist";
    is @tasks[0].body.elems, 0, "No notes found";


    my $day = DateTime.now.local.Date.succ.Str;
    $task.task-set-maturity(1, $day);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].not-before.Str, $day, "Not-before header correct";
    is @tasks[0].body.elems, 1, "One note found";

    my $expected = "Added not-before date: $day";
    is @tasks[0].body[0].text, $expected, "Note is correct";


    $task.task-set-maturity(1, Date.new($day).succ.Str);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].not-before.Str, Date.new($day).succ.Str, "Not-before header correct";
    is @tasks[0].body.elems, 2, "Two notes found";

    $expected = "Updated not-before date from $day to " ~ $day.succ;
    is @tasks[0].body[1].text, $expected, "Note is correct";

    is $task.LOCKCNT, 0, "Lock count is 0";

    done-testing;
}

tests();

