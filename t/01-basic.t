use v6.c;
use Test;
use App::Tasks;

use File::Temp;

my $tmpdir = tempdir.IO;    # Get IO::Path object for tmpdir.
note "# Using directory {$tmpdir.Str}";

my $cwd = $*CWD;
say $*CWD;

my $task = App::Tasks.new( :data-dir($tmpdir) );

is $task.WHAT, App::Tasks, "Initialized class";
is $task.data-dir, $tmpdir, "Data directory matches";
ok $task.data-dir.d, "Data directory exists";

is $task.LOCKCNT, 0, "Lock count is 0";
is $task.get-task-filenames.elems, 0, "Proper number of tasks";
is $task.LOCKCNT, 0, "Lock count is 0";
is $task.get-next-sequence.Int, 1, "Proper next sequence";
is $task.LOCKCNT, 0, "Lock count is 0";

is $cwd, $*CWD, "Current working directory unchanged";

done-testing;
