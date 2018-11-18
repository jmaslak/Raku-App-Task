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

    subtest "init", {
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 0, "No notes found";
        is @tasks[0].tags.elems, 0, "tags defined";
    }

    subtest "first tag", {
        my $tags = SetHash.new;
        $tags<test1> = True;

        $task.add-tag(1, 'test1');
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 1, "One note found";
        is @tasks[0].body[0].text, "Added tag test1", "Note[0] is correct";
        is @tasks[0].tags.sort.list, $tags.sort.list, "tags proper";
    }

    subtest "duplicate tag", {
        my $tags = SetHash.new;
        $tags<test1> = True;

        $task.add-tag(1, 'test1');
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 1, "One note found";

        is @tasks[0].body[0].text, "Added tag test1", "Note[0] is correct";

        is @tasks[0].tags.sort.list, $tags.sort.list, "tags proper";
    }

    subtest "second tag", {
        my $tags = SetHash.new;
        $tags<test1> = True;
        $tags<test2> = True;

        $task.add-tag(1, 'test2');
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 2, "Two notes found";

        is @tasks[0].body[0].text, "Added tag test1", "Note[0] is correct";
        is @tasks[0].body[1].text, "Added tag test2", "Note[1] is correct";

        is @tasks[0].tags.sort.list, $tags.sort.list, "tags proper";
    }

    subtest "remove unset tag", {
        my $tags = SetHash.new;
        $tags<test1> = True;
        $tags<test2> = True;

        $task.remove-tag(1, 'test-bogus');
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 2, "Two notes found";

        is @tasks[0].body[0].text, "Added tag test1", "Note[0] is correct";
        is @tasks[0].body[1].text, "Added tag test2", "Note[1] is correct";

        is @tasks[0].tags.sort.list, $tags.sort.list, "tags proper";
    }

    subtest "remove first tag", {
        my $tags = SetHash.new;
        $tags<test2> = True;

        $task.remove-tag(1, 'test1');
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 3, "Three notes found";

        is @tasks[0].body[0].text, "Added tag test1", "Note[0] is correct";
        is @tasks[0].body[1].text, "Added tag test2", "Note[1] is correct";
        is @tasks[0].body[2].text, "Removed tag test1", "Note[2] is correct";

        is @tasks[0].tags.sort.list, $tags.sort.list, "tags proper";
    }

    subtest "remove second tag", {
        my $tags = SetHash.new;

        $task.remove-tag(1, 'test2');
        my @tasks = $task.read-tasks;
        is @tasks.elems, 1, "Proper number of tasks exist";
        is @tasks[0].title, "Subject Line", "Proper subject line";
        is @tasks[0].body.elems, 4, "Four notes found";

        is @tasks[0].body[0].text, "Added tag test1", "Note[0] is correct";
        is @tasks[0].body[1].text, "Added tag test2", "Note[1] is correct";
        is @tasks[0].body[2].text, "Removed tag test1", "Note[2] is correct";
        is @tasks[0].body[3].text, "Removed tag test2", "Note[3] is correct";

        is @tasks[0].tags.sort.list, $tags.sort.list, "tags proper";
    }

    is $task.get-lock-count, 0, "Lock count is 0";

    done-testing;
}

tests();

