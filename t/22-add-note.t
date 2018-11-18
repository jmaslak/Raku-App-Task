use v6.c;
use Test;
use App::Tasks;
use App::Tasks::Config;

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
    my $task = App::Tasks.new( :data-dir($tmpdir), :config(App::Tasks::Config.no-color) );

    my @lines = (
        'Subject Line',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new(), 1, "Added new task";

    my @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist (A)";
    is @tasks[0].title, "Subject Line", "Proper subject line (1)";
    is @tasks[0].task-number, 1, "Proper number (A1)";

    #
    # First Note
    #
    $task.task-add-note(1, "A Note.");

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist (B)";
    is @tasks[0].title, "Subject Line", "Proper subject line (B)";
    is @tasks[0].task-number, 1, "Proper number (B1)";
    is @tasks[0].body.elems, 1, "Proper number of body elements";
    is @tasks[0].body[0].text, "A Note.", "Proper body text";
    ok @tasks[0].body[0].date.defined, "Date field defined";

    is $task.get-lock-count, 0, "Lock count is 0";

    #
    # Second Note
    #
    $task.task-add-note(1, "B Note.");

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist (B)";
    is @tasks[0].title, "Subject Line", "Proper subject line (B)";
    is @tasks[0].task-number, 1, "Proper number (B1)";
    is @tasks[0].body.elems, 2, "Proper number of body elements";
    is @tasks[0].body[0].text, "A Note.", "Proper body text";
    ok @tasks[0].body[0].date.defined, "Date field defined";
    is @tasks[0].body[1].text, "B Note.", "Proper body text";
    ok @tasks[0].body[1].date.defined, "Date field defined";

    is $task.get-lock-count, 0, "Lock count is 0";

    done-testing;
}

tests();

