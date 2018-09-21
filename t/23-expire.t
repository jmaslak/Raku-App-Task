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
    is @tasks[0].expires.defined, False, "Expires header does not exist";
    is @tasks[0].body.elems, 0, "No notes found";


    my $day = DateTime.now.local.Date.Str;
    $task.task-set-expiration(1, $day);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].expires.Str, $day, "Expires header correct";
    is @tasks[0].body.elems, 1, "One note found";

    my $expected = "Added expiration date: $day";
    is @tasks[0].body[0].text, $expected, "Note is correct";


    $task.task-set-expiration(1, Date.new($day).succ.Str);

    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].expires.Str, Date.new($day).succ.Str, "Expires header correct";
    is @tasks[0].body.elems, 2, "Two notes found";

    $expected = "Updated expiration date from $day to " ~ $day.succ;
    is @tasks[0].body[1].text, $expected, "Note is correct";

    is $task.LOCKCNT, 0, "Lock count is 0";


    @lines = (
        '2 Subject Line',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new-expire-today(), 2, "Added new task";

    $day = DateTime.now.local.Date.Str;

    @tasks = $task.read-tasks;
    is @tasks.elems, 2, "Proper number of tasks exist";
    is @tasks[1].title, "2 Subject Line", "Proper subject line";
    is @tasks[1].body.elems, 1, "One note found";

    is @tasks[1].expires.Str, $day, "Expires header correct";
    is @tasks[1].body.elems, 1, "One note found";

    $expected = "Added expiration date: $day";
    is @tasks[1].body.[0].text, $expected, "Note is correct";

    $task.set-expiration(1, Date.new($day).pred);

    @tasks = $task.read-tasks;
    is @tasks.elems, 2, "B: Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "B: Proper subject line";
    is @tasks[0].expires, Date.new($day).pred.Str, "B: Expires header correct";
    is @tasks[0].body.elems, 3, "B: Three notes found";

    $task.expire();
    
    @tasks = $task.read-tasks;
    is @tasks.elems, 1, "C: Proper number of tasks exist";
    is @tasks[0].title, "2 Subject Line", "C: Proper subject line";

    done-testing;
}

tests();

