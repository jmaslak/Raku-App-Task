use v6.c;
use Test;
use App::Tasks;
use App::Tasks::Config;
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
    my $task = App::Tasks.new( :data-dir($tmpdir), :config(App::Tasks::Config.no-color) );

    my @lines = (
        'Subject Line',
        'n',
        '',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    is $task.task-new(), 1, "Added new task";

    my $day = DateTime.now.local.Date.Str;
    $task.task-set-expiration(1, $day);

    my @tasks = $task.read-tasks;
    is @tasks.elems, 1, "Proper number of tasks exist";
    is @tasks[0].title, "Subject Line", "Proper subject line";
    is @tasks[0].body.elems, 1, "One note found";
    is @tasks[0].expires.Str, $day, "Expires header correct";
    is @tasks[0].version, 2, "Version is correct";
    is @tasks[0].task-id.defined, True, "Task ID is defined";

    my $one = App::Tasks::Task.from-file( $tmpdir, 1 );
    is $one.title,               @tasks[0].title,              "field matches: title";
    is $one.created.posix,       @tasks[0].created.posix,      "field matches: created";
    is $one.expires,             @tasks[0].expires,            "field matches: expires";
    is $one.body.elems,          @tasks[0].body.elems,         "body count matches";
    is $one.body[0].date.posix,  @tasks[0].body[0].date.posix, "body date matches";
    is $one.body[0].text,        @tasks[0].body[0].text,       "body text matches";
  
    $one.change-title: "Foo Bar";  # Set this to an invalid title, that should get overwritten when refreshed.
    $one.refresh-task; # Refresh the task from a file. 
    todo "Refresh doesn't actually do anything yet";
    is $one.title,               @tasks[0].title,              "refreshed: field matches: title";
    is $one.created.posix,       @tasks[0].created.posix,      "refreshed: field matches: created";
    is $one.expires,             @tasks[0].expires,            "refreshed: field matches: expires";
    is $one.body.elems,          @tasks[0].body.elems,         "refreshed: body count matches";
    is $one.body[0].date.posix,  @tasks[0].body[0].date.posix, "refreshed: body date matches";
    is $one.body[0].text,        @tasks[0].body[0].text,       "refreshed: body text matches";

    my @orig = $tmpdir.add("00001-none.task").lines.sort.list;
    $one.to-file;
    my @new  = $tmpdir.add("00001-none.task").lines.sort.list;
    todo "This will have a changed title now";
    is-deeply @new, @orig, "to-file works properly";

    my @rand = (^1_000).map: { App::Tasks::Task::new-task-id };
    is @rand.elems, @rand.unique.elems, "No duplications of TaskIDs";

    is $task.get-lock-count, 0, "Lock count is 0";

    $one.update-trello-id('trello id');
    dies-ok { $one.add_note("Note") }, "Can't add a note to a Trello task";

    done-testing;
}

tests();
