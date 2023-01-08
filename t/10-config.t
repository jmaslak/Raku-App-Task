use v6.c;
use Test;
use App::Tasks::Config;

use File::Temp;
use Terminal::ANSIColor;
use YAMLish;

subtest 'basic-dark', {
    my ($fn, $fh) = tempfile;
    $fh.say: "theme: dark";
    $fh.say: "immature-task-color: 'bold red'";
    $fh.close;

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    is $conf.body-color, color('reset yellow'), "Body color is proper";
    is $conf.immature-task-color, color('reset bold red'), "Immature task color is proper";

    done-testing;
}

subtest 'basic-light', {
    my ($fn, $fh) = tempfile;
    $fh.say: "theme: light";
    $fh.close;

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    is $conf.body-color, color('reset 94'), "Body color is proper";

    done-testing;
}

subtest 'basic-none', {
    my ($fn, $fh) = tempfile;
    $fh.say: "theme: 'no-color'";
    $fh.close;

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    is $conf.body-color, '', "Body color is proper";

    done-testing;
}

subtest 'empty', {
    my ($fn, $fh) = tempfile;
    $fh.close;

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    is $conf.body-color, color('reset yellow'), "Body color is proper";

    done-testing;
}

subtest 'none', {
    my $fn = '/does/not/really/exist/at/all/anywhere/i/hope';

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    is $conf.body-color, color('reset yellow'), "Body color is proper";
    is $conf.ignore-tags.elems, 0, "No ignore tags present";

    done-testing;
}

subtest 'editor-pager', {
    my ($fn, $fh) = tempfile;
    $fh.say: "editor-command: 'foo %FILENAME%'";
    $fh.say: "pager-command:  'bar %PROMPT% %FILENAME%'";
    $fh.close;

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.editor-command, 'foo %FILENAME%', 'pager command';
    is $conf.pager-command, 'bar %PROMPT% %FILENAME%', 'prompt command';
}

subtest 'ignore-tags', {
    my ($fn, $fh) = tempfile;
    $fh.say: "ignore-tags:";
    $fh.say: " - abc";
    $fh.say: " - def";
    $fh.close;

    my $conf = App::Tasks::Config.read-config($fn.IO);

    is $conf.WHAT, App::Tasks::Config, "Initialized class";

    my @expected = ('abc', 'def');
    is $conf.ignore-tags.keys.sort.list, @expected.sort.list, "ignore tags as expected";

    done-testing;
}

subtest 'display-time', {
    my ($fn, $fh) = tempfile;
    $fh.say: "monitor:";
    $fh.say: "  display-time: No";
    $fh.close;
    my $conf = App::Tasks::Config.read-config($fn.IO);
    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    my @expected = False;
    is $conf.monitor.display-time, False, "Do not display time";

    ($fn, $fh) = tempfile;
    $fh.say: "monitor:";
    $fh.say: "  display-time: Yes";
    $fh.close;
    $conf = App::Tasks::Config.read-config($fn.IO);
    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    @expected = False;
    is $conf.monitor.display-time, True, "Do display time";

    ($fn, $fh) = tempfile;
    $fh.close;
    $conf = App::Tasks::Config.read-config($fn.IO);
    is $conf.WHAT, App::Tasks::Config, "Initialized class";
    @expected = False;
    is $conf.monitor.display-time, True, "Do display time (default)";

    done-testing;
}

done-testing;

