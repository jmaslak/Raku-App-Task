use v6.c;
use Test;
use App::Tasks;

use File::Temp;

my $tmpdir = tempdir.IO;    # Get IO::Path object for tmpdir.
note "# Using directory {$tmpdir.Str}";

my $task = App::Tasks.new( :data-dir($tmpdir) );

is $task.WHAT, App::Tasks, "Initialized class";
is $task.data-dir, $tmpdir, "Data directory matches";
ok $task.data-dir.d, "Data directory exists";

is $task.get-task-filenames.elems, 0, "Proper number of tasks";
is $task.get-next-sequence.Int, 1, "Proper next sequence";

done-testing;
