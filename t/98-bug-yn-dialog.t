use v6.c;

# Y/N dialog was accepting invalid characters

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

    #
    # Valid N
    #

    my @lines = (
        'N',
        'n',
        'no',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    $task.write-output = False;

    for @lines -> $val {
        is $task.yn-prompt(""), False, "Testing $val --> False";
    }

    #
    # Valid Y
    #

    @lines = (
        'Y',
        'y',
        'yes',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    $task.write-output = False;

    for @lines -> $val {
        is $task.yn-prompt(""), True, "Testing $val --> True";
    }

    #
    # Invalid
    #
    @lines = (
        'yeppers',
        'y',
        'n',
    );
    $task.INFH = MockInFH.new( :lines(@lines) );
    $task.write-output = False;

    is $task.yn-prompt(""), True, "Testing invalid followed by valid";
    is $task.yn-prompt(""), False, "Testing terminating false";

    is $task.get-lock-count, 0, "Lock count is 0";

    done-testing;
}

tests();

