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
    note "# Using directory {$tmpdir.Str}";

    my $task = App::Tasks.new( :data-dir($tmpdir), :config(App::Tasks::Config.no-color) );

    my @lines = (
        'Subject Line',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new(), 1, "Added new task";

    my @tasks = $task.read-tasks;
    is @tasks.elems, 1, "0 Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "0 Proper subject line";
    is @tasks[0].not-before.defined, False, "0 Not-before header does not exist";
    is @tasks[0].body.elems, 0, "0 No notes found";
    is @tasks[0].display-frequency.defined, False, "0 Display frequency not defined";
    is @tasks[0].frequency-display-today, True, "0 Display frequency today";

    $task.task-set-frequency(1, 1);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "A Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "A Proper subject line";
    is @tasks[0].not-before.defined, False, "A Not-before header does not exist";
    is @tasks[0].display-frequency, 1, "A Display frequency is 1";
    is @tasks[0].frequency-display-today, True, "A Display frequency today";
    is @tasks[0].body.elems, 1, "A One note found";
    my $expected = "Added display frequency of every 1 days";
    is @tasks[0].body[0].text, $expected, "A Note is correct";

    $task.task-set-frequency(1, 1_000_000_000_000);  # Unlikely to match!

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "B Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "B Proper subject line";
    is @tasks[0].not-before.defined, False, "B Not-before header does not exist";
    is @tasks[0].display-frequency, 1_000_000_000_000, "B Display frequency is 1_000_000_000_000";
    is @tasks[0].frequency-display-today, False, "B Display frequency today";
    is @tasks[0].body.elems, 2, "B One note found";
    $expected = "Added display frequency of every 1 days";
    is @tasks[0].body[0].text, $expected, "B Note 1 is correct";
    $expected = "Updated display frequency from every 1 days to every 1000000000000 days";
    is @tasks[0].body[1].text, $expected, "B Note 2 is correct";

    is $task.LOCKCNT, 0, "Lock count is 0";

    done-testing;
}

tests();

