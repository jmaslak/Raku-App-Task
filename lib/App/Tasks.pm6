#
# Copyright © 2015-2018 Joelle Maslak
# All Rights Reserved
#
use v6.c;

class App::Tasks:ver<0.0.17>:auth<cpan:JMASLAK> {
    use App::Tasks::Config;
    use App::Tasks::Lock;
    use App::Tasks::Task;
    use App::Tasks::TaskList;

    use Digest::SHA1::Native;
    use File::Temp;
    use NativeCall;
    use P5getpriority;
    use P5localtime;
    use Term::termios;
    use Term::ReadKey;
    use Terminal::ANSIColor;

    my $P1         = '[task]';
    my $P2         = '> ';

    has Lock:D $.SEMAPHORE = Lock.new;
    has App::Tasks::Task:D @!TASKS;

    has IO::Path:D             $.data-dir = gettaskdir;
    has App::Tasks::Config:D   $.config   = App::Tasks::Config.read-config(:data-dir($!data-dir));
    has App::Tasks::TaskList:D $!tasks    = App::Tasks::TaskList.new(:data-dir($!data-dir));

    # Partially implemented - there be dragons here!
    has $.write-output is rw = True;   # Write output to terminal, used for testing only.
    has $.INFH         is rw = $*IN;   # Input Filehandle

    # Disable freshness check
    has $!check-freshness = True;

    # Fix %*ENV<SHELL> so LESS doesn't give error messages
    if %*ENV<SHELL>:exists {
        if %*ENV<SHELL> eq '-bash' {
            %*ENV<SHELL> = 'bash';
        }
    }

    my %H_INFO = (
        title => {
            order        => 1,
            display      => 'Title',
        },
        created => {
            order        => 2,
            display      => 'Created',
        },
        not-before => {
            order        => 3,
            display      => 'Not-Before',
            alert-before => True,
        },
        expires => {
            order        => 4,
            display      => 'Expires',
            alert-expire => True,
        },
        display-frequency => {
            order        => 5,
            display      => 'Display-Frequency',
        },
        task-id => {
            order        => 6,
            display      => 'Task-ID',
            hex          => True,
        },
        tags => {
            order        => 7,
            display      => 'Tags',
        },
    );

    my $H_LEN = %H_INFO.values.map( { .<display>.chars } ).max;

    method start(
        @args is copy,
        Bool :$expire-today? = False,
        Bool :$show-immature? is copy = False,
        Bool :$all? = False,
        Date :$maturity-date?,
        App::Tasks::Task::Tag :$tag?,
    ) {
        $*OUT.out-buffer = False;

        # If all is set, it implies show-immature.
        $show-immature = True if $all;

        if ! @args.elems {

            my @choices = (
                [ 'Create New Task',            'new' ],
                [ 'Add a Note to a Task',       'note' ],
                [ 'View an Existing Task',      'show' ],
                [ 'List All Tasks',             'list' ],
                [ 'Monitor Task List',          'monitor' ],
                [ 'Move (Reprioritize) a Task', 'move' ],
                [ 'Close a Task',               'close' ],
                [ 'Coalesce Tasks',             'coalesce' ],
                [ 'Retitle Tasks',              'retitle' ],
                [ 'Set Task Expiration',        'set-expire' ],
                [ 'Expire Tasks',               'expire' ],
                [ 'Set Task Maturity Date',     'set-maturity' ],
                [ 'Set Task Display Frequency', 'set-frequency' ],
                [ 'Add Tag',                    'add-tag' ],
                [ 'Remove Tag',                 'remove-tag' ],
                [ 'Quit to Shell',              'quit' ],
            );

            say "{$.config.prompt-color}Please select an option...\n";
            my $command = self.menu-prompt("$P1 $P2", @choices);
            @args.push($command // 'quit');

            if ( @args[0] eq 'quit' ) { exit; }
        }

        if @args.elems == 1 {
            if @args[0] ~~ m/^ \d+ $/ {
                @args.unshift: 'view';      # We view the task if one arg entered
            }
        }

        my @validtasks = $!tasks.get-task-filenames().map( { Int( S/ ^ .* ( <[0..9]>+ ) \- .* $/$0/ ); } );

        my $cmd = @args.shift.fc;
        given $cmd {
            when $_ eq 'new' or $_ eq 'add' {
                if $maturity-date and $expire-today {
                    die("Cannot use both the --expire-today and --maturity-date options simultaniously\n");
                } elsif $maturity-date {
                    if $expire-today {
                        die("Cannot use both the --expire-today and --maturity-date options simultaniously\n");
                    }
                    my $old = $!check-freshness;
                    $!check-freshness = False;
                    self.task-new-maturity(|@args, :$maturity-date, :$tag);
                    $!check-freshness = $old;
                } elsif $expire-today {
                    my $old = $!check-freshness;
                    $!check-freshness = False;
                    self.task-new-expire-today(|@args, :$tag);
                    $!check-freshness = $old;
                } else {
                    self.task-new(|@args, :$tag);
                }
            }
            when 'move' {
                if @args[0]:!exists {
                    @args[0] = self.no-menu-prompt(
                        "$P1 Please enter source task number to move $P2",
                        @validtasks
                    ).Int or exit;
                }
                if @args[1]:!exists {
                    @args[1] = self.uint-prompt( "$P1 Please enter desired location of task $P2" ) or exit;
                }
                self.task-move(|@args);
            }
            when $_ ~~ 'show' or $_ ~~ 'view' {
                if @args[0]:!exists {
                    @args[0] = self.no-menu-prompt(
                        "$P1 Please enter task number to show $P2",
                        @validtasks
                    ).Int or exit;
                    say "";
                }
                self.task-show(|@args);
            }
            when 'note' {
                if @args[0]:!exists {
                    @args[0] = self.no-menu-prompt(
                        "$P1 Please enter task number to modify $P2",
                        @validtasks
                    ).Int or exit;
                    @args[0] = @args[0].Int;
                    say "";
                }
                self.task-add-note(|@args);
            }
            when $_ ~~ 'close' or $_ ~~ 'commit' {
                if @args[0]:!exists {
                    @args[0] = self.prompt(
                        "$P1 Please enter task number to close $P2",
                        [@validtasks]
                    ).Int or exit;
                    say "";
                }
                self.task-close(|@args);
            }
            when 'list' { self.task-list(|@args, :$show-immature, :$all, :$tag) }
            when 'monitor' { self.task-monitor(|@args, :$show-immature, :$all, :$tag) }
            when 'coalesce' { self.task-coalesce(|@args) }
            when 'retitle' { self.task-retitle(|@args) }
            when 'set-expire' { self.task-set-expiration(|@args) }
            when 'expire' { self.expire(|@args) }
            when 'set-maturity' { self.task-set-maturity(|@args) }
            when 'set-frequency' { self.task-set-frequency(|@args) }
            when 'add-tag' { self.task-add-tag(|@args) }
            when 'remove-tag' { self.task-remove-tag(|@args) }
            default {
                say "WRONG USAGE";
            }
        }
    }

    # Indirectly tested
    method get-next-sequence(-->Int) {
        self.add-lock();
        LEAVE self.remove-lock;

        my @tasks = self.read-tasks();

        my Int $seq = 1;
        if @tasks.elems {
            $seq = @tasks.map({ $^a.task-number }).max + 1;
            if $seq > 99999 { die("Task number would be too large"); }
        }

        return $seq;
    }

    # Has test
    method task-new-expire-today(Str $sub?, App::Tasks::Task::Tag :$tag) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = self.task-new($sub, :$tag);
        self.task-set-expiration($task.Int, DateTime.now.local.Date.Str);

        return $task;
    }

    # Has test
    method task-new-maturity(Str $sub?, Date:D :$maturity-date, App::Tasks::Task::Tag :$tag) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = self.task-new($sub, :$tag);
        self.task-set-maturity($task.Int, $maturity-date.Str);

        return $task;
    }


    # Has test
    method task-new(Str $sub?, App::Tasks::Task::Tag :$tag) {
        self.add-lock;
        LEAVE self.remove-lock;

        my Int $seq = self.get-next-sequence;

        my $subject;
        if ! defined($sub) {
            $subject = self.str-prompt( "$P1 Enter Task Subject $P2" ) or exit;
        } else {
            $subject = $sub;
        }

        $subject ~~ s/^\s+//;
        $subject ~~ s/\s+$//;
        $subject ~~ s:g/\t/ /;
        if ( $subject eq '' ) { say "Blank subject, exiting."; exit; }
        say "";

        my $body;
        if ! defined($sub) {
            $body = self.get-note-from-user();

            if ! self.confirm-save() {
                say "Aborting.";
                exit;
            }
        }

        my $tags = SetHash.new;
        $tags{$tag} = True if $tag.defined;

        my $task = App::Tasks::Task.new(
            :task-number($seq),
            :data-dir($!tasks.data-dir),
            :title($subject),
            :created(DateTime.now),
            :tags($tags),
        );

        if defined($body) {
            $task.add-note($body);
        }

        $task.to-file;
        @!TASKS.push($task);

        say "Created task $seq";
        return $seq;
    }

    # Indirectly tested
    method get-task-filename(Int $taskint where * ~~ ^100_000 --> IO::Path:D) {
        self.add-lock;
        LEAVE self.remove-lock;

        my Str $task = sprintf( "%05d", $taskint );

        my @d = $!tasks.get-task-filenames();
        my @fn = @d.grep: { .basename ~~ m/^ $task '-'/ };

        if @fn.elems > 1  { die "More than one name matches\n"; }
        if @fn.elems == 1 { return @fn[0]; }

        die("Task not found");
    }

    # Tested
    method task-move(Int $old where * ~~ ^100_000, Int $new where * ~~ ^100_000) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! self.check-task-log() {
            say "Can't move task - task numbers may have changed since last 'task list'";
            return;
        }

        my Int $end = self.get-next-sequence;
        if ( $new >= $end ) {
            $new = $end - 1;
        }
        if ( $new < 1 ) { $new = 1; }

        my $oldfn = self.get-task-filename($old);

        my $oldbase = $oldfn.basename;
        my $newbase = S/^ \d+ '-'/-/ given $oldbase;
        my $newfn = $oldfn.parent.add: sprintf( "%05d%s", $new, $newbase);

        my $newfntmp = $oldfn.parent.add: $newfn.basename ~ '.tmp';

        move $oldfn, $newfntmp;

        my @d = $!tasks.get-task-filenames();

        if ( $new < $old ) { @d = reverse @d; }
        for @d -> $f {
            my $num = $f.basename;
            $num ~~ s/'-' .* $//;
            if $num == $old {

                # Skip the file that isn't there anymore
                next;
            }

            my $suffix = $f.basename;
            $suffix ~~ s/^ \d+ '-'/-/;

            if $new < $old {
                if ( ( $num >= $new ) && ( $num <= $old ) ) {
                    $num = sprintf( "%05d", $num + 1 );
                    move $f, $f.parent.add("$num$suffix");
                }
            } elsif ( $new > $old ) {
                if ( ( $num <= $new ) && ( $num >= $old ) ) {
                    $num = sprintf( "%05d", $num - 1 );
                    move $f, $f.parent.add("$num$suffix");
                }
            }
        }

        move $newfntmp, $newfn;
    }

    method task-show(Int $tasknum where * ~~ ^100_000) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! $!tasks.exists($tasknum) {
            $*ERR.say("Could not locate task number $tasknum");
            return;
        }

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);

        my $out    = '';

        # Headers
        $out ~= self.sprint-header-line: 'title', $task.title;
        $out ~= self.sprint-header-line: 'created', $task.created;
        $out ~= self.sprint-header-line: 'not-before', $task.not-before, :alert-in-past(False) if $task.not-before.defined;
        $out ~= self.sprint-header-line: 'expires', $task.expires, :alert-in-past if $task.expires.defined;
        $out ~= self.sprint-header-line: 'display-frequency', $task.display-frequency if $task.display-frequency.defined;
        $out ~= self.sprint-header-line: 'task-id', $task.task-id;
        $out ~= self.sprint-header-line: 'tags', $task.tags.keys.sort.join(' ') if $task.tags.elems;

        $out ~= "\n";

        if $task.body.elems {
            $out ~= $task.body.map( { self.sprint-body($^a) } ).join("\n\n") ~ "\n";
        }

        self.display-with-pager( "Task $tasknum", $out );
    }

    # Indirectly tested
    method read-task-body(Hash $task is rw, @lines) {
        self.add-lock();
        LEAVE self.remove-lock;

        for @lines -> $line {
            if $line ~~ m/^ '--- ' (\d+) $/ {
                my $bodydate = $0.Int;
                my $body = Hash.new;
                $body<date> = $bodydate;
                $body<body> = [];

                $task<body>.push: $body;
                next;
            }

            if $task<body> {
                $task<body>[*-1]<body> ~= $line ~ "\n";
            }
        }
    }

    multi method sprint-header-line(Str:D $header, Str:D $value, Bool :$alert?) {
        my $out = '';

        my $len = $H_LEN;

        $out ~= $.config.header-title-color;
        $out ~= sprintf( "%-{$len}s : ", %H_INFO{$header}<display> );
        if $alert {
            $out ~= $.config.header-alert-color;
        } else {
            $out ~= $.config.header-normal-color;
        }
        $out ~= $value;
        $out ~= $.config.reset;
        $out ~= "\n";

        return $out;
    }

    multi method sprint-header-line(
        Str:D $header,
        Date:D $value,
        Bool:D :$alert-in-past?
    ) {
        my $parsed = self.pretty-day($value);
        if Date.new($value) < Date.new(DateTime.now.local.Date.Str) {
            return self.sprint-header-line: $header, "$parsed (expired)", :alert;
        } elsif Date.new($value) > Date.new(DateTime.now.local.Date.Str) {
            return self.sprint-header-line: $header, "$parsed (future)", :alert;
        } else {
            return self.sprint-header-line: $header, $parsed;
        }
    }

    multi method sprint-header-line(Str:D $header, DateTime:D $value) {
        return self.sprint-header-line: $header, localtime(Scalar, $value.posix);
    }

    multi method sprint-header-line(Str:D $header, Int:D $value) {
        if %H_INFO{$header}<hex> {
            return self.sprint-header-line: $header, $value.fmt("%x");
        } else {
            return self.sprint-header-line: $header, $value.Str;
        }
    }

    method sprint-body(App::Tasks::TaskBody $body) {
        my $out = $.config.header-alert-color ~ "["
            ~ localtime(Scalar, $body.date.posix) ~ "]"
            ~ $.config.header-seperator-color ~ ':'
            ~ $.config.reset ~ "\n";

        my $coloredtext = $body.text;
        my $bcolor = $.config.body-color;
        $coloredtext   ~~ s:g/^^/$bcolor/;

        $out ~= $coloredtext ~ $.config.reset;

        return $out;
    }

    # Tested
    method task-retitle(Int $tasknum? where { !$tasknum.defined or $tasknum > 0 }, Str $newtitle? is copy) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! self.check-task-log {
            say "Can't retitle - task numbers may have changed since last 'task list'";
            return;
        }

        $tasknum //= self.ask-for-tasknum;

        if !$newtitle.defined or $newtitle eq '' {
            $newtitle = self.str-prompt("$P1 Please enter the new title $P2");
        }

        return self.retitle($tasknum, $newtitle);
    }

    # Indirectly tested
    method retitle(Int $tasknum where * ~~ ^100_000, Str:D $newtitle) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);
        my $note = "Title changed from:\n" ~
                "  " ~ $task.title ~ "\n" ~
                "To:\n" ~
                "  " ~ $newtitle;

        $task.add-note($note);
        $task.change-title($newtitle);
        $task.to-file;

        @!TASKS = Array.new;
        return;
    }

    # Tested
    method expire() {
        self.add-lock;
        LEAVE self.remove-lock;

        my @tasks = self.read-tasks();
        for @tasks -> $task {
            if $task.expires.defined {
                if $task.expires < Date.new(DateTime.now.local.Date.Str) {
                    $task.add-note("Task expired, closed.");
                    $task.to-file;
                    self.task-close($task.task-number, :coalesce(False), :interactive(False));
                }
            }
        }
        self.coalesce-tasks();

        @!TASKS = Array.new;
    }

    # Tested
    method task-set-expiration(Int $tasknum? is copy where { !$tasknum.defined or $tasknum > 0 }, Str $day? is copy) {
        self.add-lock;
        LEAVE self.remove-lock;

        if $day.defined {
            if $day !~~ m/^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/ {
                say "Invalid date format - please use YYYY-MM-DD format";
                return;
            }
        }

        if ! self.check-task-log() {
            say "Can't set expiration - task numbers may have changed since last 'task list'";
            return;
        }

        $tasknum //= self.ask-for-tasknum;

        while !$day.defined or $day eq '' {
            $day = self.str-prompt("$P1 Please enter the last valid day for this task $P2");
            if $day !~~ m/^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/ {
                say "Date format is incorrect\n";
                $day = '';
            }
        }

        my $now    = Date.new(DateTime.now.local.Date.Str);
        my $expire = Date.new($day);

        if $expire < $now {
            say "Date cannot be before today";
            return;
        }

        return self.set-expiration($tasknum, $expire);
    }

    # Indirectly tested
    method set-expiration(Int $tasknum where * ~~ ^100_000, Date:D $day) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);

        my $note;
        if $task.expires.defined {
            $note = "Updated expiration date from " ~ $task.expires.Str ~ " to $day";
        } else {
            $note = "Added expiration date: $day";
        }

        $task.add-note($note);
        $task.change-expiration($day);
        $task.to-file;

        @!TASKS = Array.new;
        return;
    }

    # Tested
    method task-set-maturity(Int $tasknum? is copy where { !$tasknum.defined or $tasknum > 0 }, Str $day? is copy) {
        self.add-lock;
        LEAVE self.remove-lock;

        if $day.defined {
            if $day !~~ m/^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/ {
                say "Invalid date format - please use YYYY-MM-DD format";
                return;
            }
        }

        if ! self.check-task-log() {
            say "Can't set maturity date - task numbers may have changed since last 'task list'";
            return;
        }

        $tasknum //= self.ask-for-tasknum;

        while !$day.defined or $day eq '' {
            $day = self.str-prompt("$P1 Please enter the day to start displaying this task $P2");
            if $day !~~ m/^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/ {
                say "Date format is incorrect\n";
                $day = '';
            }
        }

        my $now        = Date.new(DateTime.now.local.Date.Str);
        my $not-before = Date.new($day);

        if $not-before <= $now {
            say "Date cannot be before or equal to today";
            return;
        }

        return self.set-not-before($tasknum, $not-before);
    }

    # Tested
    method task-add-tag(
        Int $tasknum? is copy where { !$tasknum.defined or $tasknum > 0 },
        App::Tasks::Task::Tag $tag? is copy
    ) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! self.check-task-log() {
            say "Can't set tag - task numbers may have changed since last 'task list'";
            return;
        }

        $tasknum //= self.ask-for-tasknum;
        $tag     //= self.ask-for-tag;

        return self.add-tag($tasknum, $tag);
    }

    # Tested
    method task-remove-tag(
        Int $tasknum? is copy where { !$tasknum.defined or $tasknum > 0 },
        App::Tasks::Task::Tag $tag? is copy
    ) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! self.check-task-log() {
            say "Can't set tag - task numbers may have changed since last 'task list'";
            return;
        }

        $tasknum //= self.ask-for-tasknum;
        $tag     //= self.ask-for-tag;

        return self.remove-tag($tasknum, $tag);
    }

    # Tested
    method task-set-frequency(Int $tasknum? is copy where { !$tasknum.defined or $tasknum > 0 }, Int $frequency? is copy) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! self.check-task-log() {
            say "Can't set display frequency - task numbers may have changed since last 'task list'";
            return;
        }

        $tasknum //= self.ask-for-tasknum;

        while ! $frequency.defined {
            my $s = self.str-prompt("$P1 Please enter desired days apart for task display $P2");
            if $s !~~ m/^ <[1..9]> <[0..9]>* $/ {
                say "Must be an integer ≥ 1\n";
                next;
            }
            $frequency = $s.Int;
        }

        return self.set-frequency($tasknum, $frequency);
    }

    # Indirectly tested
    method set-not-before(Int $tasknum where * ~~ ^100_000, Date:D $day) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);

        my $note;
        if $task.not-before.defined {
            $note = "Updated not-before date from " ~ $task.not-before.Str ~ " to $day";
        } else {
            $note = "Added not-before date: $day";
        }

        $task.add-note($note);
        $task.change-not-before($day);
        $task.to-file;

        @!TASKS = Array.new;
    }

    # Indirectly tested
    method set-frequency(Int:D $tasknum where * ~~ ^100_000, Int:D $frequency where * ≥ 1) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);

        my $note;
        if $task.display-frequency.defined {
            $note = "Updated display frequency from every "
                ~ in-days($task.display-frequency)
                ~ " to every " ~ in-days($frequency);
        } else {
            $note = "Added display frequency of every " ~ in-days($frequency);
        }

        $task.add-note($note);
        $task.change-display-frequency($frequency);
        $task.to-file;

        @!TASKS = Array.new;
    }

    # Indirectly tested
    method add-tag(Int:D $tasknum where * ~~ ^100_000, App::Tasks::Task::Tag:D $tag) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);
        if $task.tags ∋ $tag { return };        # Don't add a duplicate

        $task.add-note: "Added tag $tag";
        $task.add-tag:  $tag;
        $task.to-file;

        @!TASKS = Array.new;
    }

    # Indirectly tested
    method remove-tag(Int:D $tasknum where * ~~ ^100_000, App::Tasks::Task::Tag:D $tag) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);
        if $task.tags ∌ $tag { return };        # Don't remove a non-existant tag

        $task.add-note:   "Removed tag $tag";
        $task.remove-tag: $tag;
        $task.to-file;

        @!TASKS = Array.new;
    }

    # Tested
    method task-add-note(Int $tasknum where * ~~ ^100_000, Str $orignote?) {
        self.add-lock;
        LEAVE self.remove-lock;

        if ! self.check-task-log() {
            say "Can't add note - task numbers may have changed since last 'task list'";
            return;
        }

        if ! $!tasks.exists($tasknum) {
            $*ERR.say("Could not locate task number $tasknum");
            return;
        }

        if ! $orignote.defined {
            self.task-show($tasknum);
        }

        my $note = $orignote;
        if !$note.defined {
            $note = self.get-note-from-user();
        }

        if ( !defined($note) ) {
            say "Not adding note";
            return;
        }

        if ! $orignote.defined and ! self.confirm-save() {
            say "Aborting.";
            exit;
        }

        return self.add-note($tasknum, $note);
    }

    # Indirectly tested
    multi method add-note(Int:D $tasknum where * ~~ ^100_000, Str:D $note) {
        self.add-lock;
        LEAVE self.remove-lock;

        my $task = App::Tasks::Task.from-file($!tasks.data-dir, $tasknum);
        return self.add-note($task, $note);
    }

    multi method add-note(App::Tasks::Task:D $task, Str:D $note) {
        self.add-lock;
        LEAVE self.remove-lock;

        $task.add-note($note);
        $task.to-file;

        say "Updated task " ~ $task.task-number;
    }

    method confirm-save() {
        my $result = self.yn-prompt(
            "$P1 Save This Task [Y/n]? $P2"
        );
        return $result;
    }

    method get-note-from-user() {
        return self.get-note-from-user-external();
    }

    method get-note-from-user-internal() {
        print color("bold cyan") ~ "Enter Note Details" ~ $.config.reset;
        say color("cyan")
            ~ " (Use '.' on a line by itself when done)"
            ~ color("bold cyan") ~ ":"
            ~ $.config.reset;

        my $body = '';
        while defined my $line = self.IN-FH.get {
            if ( $line eq '.' ) {
                last;
            }
            $body ~= $line ~ "\n";
        }

        say "";

        if ( $body eq '' ) {
            return;
        }

        return $body;
    }

    method get-note-from-user-external() {
        # External editors may pop up full screen, so you won't see any
        # history.  This helps mitigate that.
        my $result = self.yn-prompt( "$P1 Add a Note to This Task [Y/n]? $P2" );

        if !$result {
            return;
        }

        my $prompt = "Please enter any notes that should appear for this task below this line.";

        my ($filename, $tmp) = tempfile(:unlink);
        $tmp.say: $prompt;
        $tmp.say: '-' x 72;
        $tmp.close;

        my @cmd = map { S:g/'%FILENAME%'/$filename/ }, $.config.editor-command.split(/\s+/);
        run(@cmd);

        my @lines = $filename.IO.lines;
        if ! @lines.elems { return; }

        # Eat the header
        my $first = @lines[0];
        if $first eq $prompt { @lines.shift; }
        if @lines.elems {
            my $second = @lines[0];
            if $second eq '-' x 72 { @lines.shift; }
        }

        # Remove blank lines at top
        for @lines -> $line is copy {

            if $line ne '' {
                last;
            }
        }

        # Remove blank lines at bottom
        while @lines.elems {
            my $line = @lines[*-1];

            if $line eq '' {
                @lines.pop;
            } else {
                last;
            }
        }

        my $out = join "\n", @lines;
        if ( $out ne '' ) {
            return $out;
        } else {
            return;
        }
    }

    method task-close(
        Int:D  $tasknum where * ~~ ^100_000,
        Bool  :$coalesce? = True,
        Bool  :$interactive? = True
        --> Nil
    ) {
        self.add-lock;
        LEAVE self.remove-lock;

        if $interactive and ! self.check-task-log() {
            say "Can't close task - task numbers may have changed since last 'task list'";
            return;
        }
        
        if ! $!tasks.exists($tasknum) {
            $*ERR.say("Could not locate task number $tasknum");
            return;
        }

        if $interactive {
            self.task-add-note($tasknum);
        }

        my $fn = self.get-task-filename($tasknum);
        my Str $taskstr = sprintf( "%05d", $tasknum );
        $fn.basename ~~ m/^ \d+ '-' (.*) '.task' $/;
        my ($meta) = $0;
        my $newfn = time.Str ~ "-$taskstr-$*PID-$meta.task";

        self.validate-done-dir-exists();

        my $newpath = $!tasks.data-dir.add("done").add($newfn);
        move $fn, $newpath;
        say "Closed $taskstr";

        @!TASKS = Array.new;
        if $coalesce {
            self.coalesce-tasks();
        }
    }

    method display-with-pager($description, $contents) {
        my ($filename, $tmp) = tempfile(:unlink);
        $tmp.print: $contents;
        $tmp.close;

        my $out = "$description ( press h for help or q to quit ) ";

        my @pager =
            map { S:g/'%FILENAME%'/$filename/ },
            map { S:g/'%PROMPT%'/$out/ },
            $.config.pager-command.split(/\s+/);

        run(@pager);
    }

    # Tested
    method read-tasks() {
        self.add-lock;
        LEAVE self.remove-lock;

        return @!TASKS if @!TASKS.elems;

        @!TASKS = $!tasks.read-tasks;
        return @!TASKS;
    }

    method generate-task-list(
        Int $num? is copy where {!$num.defined or $num > 0},
        Int $wchars?,
        Bool :$count-immature? is copy = False,
        Bool :$count-all? = False,
        App::Tasks::Task::Tag :$tag?,
    ) {
        self.add-lock;
        LEAVE self.remove-lock;

        $count-immature = True if $count-all;

        # Filter out tasks that we don't want to include because they
        # aren't yet ripe.
        my @tasks = self.read-tasks().grep: {
            # We need to find out if we need to ignore anything
            my $ignored-tags = $^task.tags ∩ $.config.ignore-tags;

            if $tag.defined && ( $^task.tags ∌ $tag ) {
                False;
            } elsif $count-all {
                True;
            } elsif (!$tag.defined) && ($ignored-tags.elems) {
                False;  # We don't show unless --all or a tag is specified when
                        # the tags are in the ignored-tags list.
            } elsif ! $^task.frequency-display-today {
                False;
            } elsif $count-immature {
                True;  # We don't need to test to see if it is mature.
            } elsif ! $^task.is-mature {
                False;
            } else {
                True;
            }
        };

        # Limit number of tasks we display
        if $num.defined and @tasks.elems > $num {
            @tasks = @tasks[0..^$num];
        }

        if !@tasks.elems { return '' };

        my Int $maxnum = @tasks.map({ $^a.task-number }).max;

        my @out = @tasks.map: -> $task {
            my $title = $task.title;
            my $tags = '';
            if $task.tags.elems {
                $tags = '[' ~ $task.tags.keys.sort.join('] [') ~ '] ';
            }

            my $desc  = $title;
            if ( defined($wchars) ) {
                $desc = substr( $title, 0, $wchars - $maxnum.chars - 1 - $tags.chars );
            }

            my $color = $.config.prompt-bold-color;
            if ! $task.is-mature {
                $color = $.config.immature-task-color;
            } elsif ! $task.frequency-display-today {
                $color = $.config.not-displayed-today-color;
            }

            my $tcolor = $.config.tag-color;

            "{$.config.prompt-info-color}{$task.task-number} $tcolor$tags$color$desc" ~ $.config.reset ~ "\n"
        };

        return @out.join();
    }

    multi method task-list(
        Int $num? where { !$num.defined or $num > 0 },
        Bool :$show-immature? is copy = False,
        Bool :$all = True,
        App::Tasks::Task::Tag :$tag?,
    ) {
        self.add-lock;
        LEAVE self.remove-lock;

        self.update-task-log();    # So we know we've done this.
        my $out = self.generate-task-list(
            $num,
            Int,
            :count-immature($show-immature),
            :count-all($all),
            :tag($tag)
        );

        return self.display-with-pager( "Tasklist", $out );
    }
    multi method task-list( +@ ) { die "Invalid arguments" }

    method task-monitor(
        Bool :$show-immature? = False,
        Bool :$all,
        App::Tasks::Task::Tag :$tag?,
    ) {
        self.task-monitor-show();

        react {
            whenever key-pressed(:!echo) {
                say $.config.reset;
                say "";
                say "Exiting.";
                done;
            }
            whenever Supply.interval(1) {
                self.task-monitor-show(:$show-immature, :$all, :$tag);
            }
        }
    }

    method task-monitor-show(
        Bool :$show-immature? is copy = False,
        Bool :$all = False,
        App::Tasks::Task::Tag :$tag?,
    ) {
        self.add-lock;
        LEAVE self.remove-lock;

        $show-immature = True if $all;

        state $last = 'x';  # Not '' because then we won't try to draw the initial
                            # screen - there will be no "type any character" prompt!

        state ($rows, $cols) = self.get-size();
        if ($last = 'x') {
            if !defined $cols { die "Terminal not supported" }

            self.update-task-log();    # So we know we've done this.
        }

        my $out = localtime(Scalar) ~ ' local / ' ~ gmtime(Scalar) ~ " UTC\n\n";

        $out ~= self.generate-task-list(
            $rows - 3,
            $cols - 1,
            :count-immature($show-immature),
            :count-all($all),
            :$tag,
        );
        if $out ne $last {
            $last = $out;
            self.clear;
            print $out;
            print $.config.reset;
            print "     ...Type any character to exit...  ";
        }
    }

    method task-coalesce() {
        self.add-lock;
        LEAVE self.remove-lock;

        self.coalesce-tasks();

        say "Coalesced tasks";
    }

    method coalesce-tasks() {
        self.add-lock;
        LEAVE self.remove-lock;

        my @nums = $!tasks.get-task-filenames().map: { S/'-' .* .* '.task' $// given .basename };

        my $i = 1;
        for @nums.sort( {$^a <=> $^b} ) -> $num {
            if $num > $i {
                my $orig = self.get-task-filename($num.Int);

                my $newname = S/^ \d+ // given $orig.basename;
                $newname = sprintf( "%05d%s", $i, $newname);
                my $new = $orig.parent.add($newname);

                move $orig, $new;
                @!TASKS = Array.new();  # Clear cache
                $i++;
            } elsif $i == $num {
                $i++;
            }
        }
    }

    method update-task-log() {
        self.add-lock();
        LEAVE: self.remove-lock;

        my $sha = self.get-taskhash();

        my @terms;
        my $status = $!tasks.data-dir.add(".taskview.status");
        if $status.f {
            @terms = $status.lines;
        }

        my $oldhash = '';
        if (@terms) {
            $oldhash = @terms.shift;
        }

        my $tty = self.get-ttyname();

        if $oldhash eq $sha {
            # No need to update...
            if @terms.grep( { $_ eq $tty } ) {
                return;
            }
        } else {
            @terms = ();
        }

        my $fh = $status.open :w;
        $fh.say: $sha;
        for @terms -> $term {
            $fh.say: $term;
        }
        $fh.say: $tty;
        $fh.close;
    }

    # Returns true if the task log is okay for this process.
    method check-task-log() {
        # Not a TTY?  Don't worry about this.
        if ! self.isatty() { return 1; }

        # Skip freshness check?
        if ! $!check-freshness { return 1; }

        my $a = self.add-lock || True;
        LEAVE self.remove-lock with $a;

        my $sha = self.get-taskhash();

        my $status = $!tasks.data-dir.add(".taskview.status");

        my @terms;
        if $status.f {
            @terms = $status.lines;
        }

        my $oldhash = '';
        if @terms {
            $oldhash = @terms.shift;
        }

        # If hashes differ, it's not cool.
        if ( $oldhash ne $sha ) { return; }

        # If terminal in list, it's cool.
        my $tty = self.get-ttyname();
        if @terms.grep( { $^a eq $tty } ) {
            return 1;
        }

        # Not in list.
        return;
    }

    method get-taskhash() {
        self.add-lock();
        LEAVE self.remove-lock;

        my $tl = self.generate-task-list( Int, Int );
        return sha1-hex($tl);
    }

    method get-ttyname() {
        my $tty = getppid() ~ ':';
        if self.isatty() {
            $tty ~= ttyname(0);
        }

        return $tty;
    }

    method menu-prompt($prompt, @choices) {
        my %elems;

        my $max = @choices.map( { .elems } ).max;
        my $min = @choices.map( { .elems } ).min;

        if $min ≠ $min {
            die("All choice elements must be the same size");
        }

        my $cnt = 0;
        for @choices -> $choice {
            $cnt++;
            %elems{$cnt} = { description => $choice[0], value => $choice[1] };
        }

        my $width = Int(log10($cnt) + 1);

        for %elems.keys.sort({$^a <=> $^b}) -> $key {
            my $elem = %elems{$key};

            printf "{$.config.prompt-bold-color}%{$width}d.{$.config.prompt-info-color} %s\n", $key, $elem<description>;
        }

        say "";
        while defined my $line = self.prompt($prompt) {
            if %elems{$line}:exists {
                return %elems{$line}<value>;
            }

            say "Invalid choice, please try again";
            say "";
        }

        return;
    }

    method no-menu-prompt($prompt, @choices) {
        say "";
        while defined my $line = self.prompt($prompt) {
            if @choices.grep( { $^a eq $line } ) {
                return $line;
            }

            say "Invalid choice, please try again";
            say "";
        }

        return;
    }

    method uint-prompt($prompt --> Int) {
        say "";

        while defined my $line = self.prompt($prompt) {
            if $line !~~ m/ ^ \d+ $ / {
                return $line;
            }

            say "Invalid number, please try again";
            say "";
        }

        return;
    }

    method str-prompt($prompt --> Str) {
        say "";
        while defined my $line = self.prompt($prompt) {
            if $line ne '' {
                return $line;
            }

            say "Invalid input, please try again";
            say "";
        }

        return;
    }

    # Tested
    method yn-prompt($prompt --> Bool) {
        say "" if $.write-output;
        while defined my $line = self.prompt($prompt) {
            $line = $line.fc();
            if $line eq '' {
                return True;
            } elsif $line ~~ m/ ^ 'y' ( 'es' )? $ / {
                return True;
            } elsif $line ~~ m/ ^ 'n' ( 'o' )? $ / {
                return False;
            }

            say "Invalid choice, please try again" if $.write-output;
            say "" if $.write-output;
        }

        return;
    }

    method prompt($prompt) {
        my $outprompt = $.config.prompt-color ~ $prompt ~ $.config.reset;
        print $outprompt if $.write-output;
        return $.INFH.get;
    }

    method ask-for-tasknum(-->Int:D) {
        my @d = $!tasks.get-task-filenames();
        my (@validtasks) = @d.map: { $^a.basename ~~ m/^ (\d+) /; Int($0) };

        my $tn = self.no-menu-prompt(
            "$P1 Please enter task number to modify $P2",
            @validtasks
        ) or exit;

        return $tn.Int;
    }
       
    method ask-for-tag(-->App::Tasks::Task::Tag:D) { 
        loop {
            my $s = self.str-prompt("$P1 Please enter tag $P2");
            if $s !~~ m/^ \S+ $/ {
                say "Tag must not be empty or contain any spaces\n";
                next;
            }
            return $s;
        }
    }

    method clear() {
        print 27.chr, '[2J';
        self.home;
    }

    method home() {
        print 27.chr, "[;H";
    }

    # Gets terminal size
    method get-size() {
        my $oldenc = self.INFH.encoding;
        self.INFH.encoding('latin-1');       # Disable UTF processing

        my $oldin  := Term::termios.new(fd => 0).getattr;
        my $termin  := Term::termios.new(fd => 0).getattr;
        $termin.makeraw;
        $termin.setattr(:DRAIN);

        # Save cursor position
        print 27.chr, "[s";

        # Move to an absurd position using CUP
        print 27.chr, "[9999;9999H";

        # Where is the cursor? Ask for the DSR
        print 27.chr, "[6n";

        # Unsave cursor position
        print 27.chr, "[u";

        # We look for a CPR (Active Position Report)
        my Int $rowsize;
        my Int $colsize;
        loop (;;) {
            while self.INFH.getc.ord ≠ 27 { }
            if self.INFH.getc ne '[' { next }

            # Okay, we have a CPR.
            # Get lines
            my $lines = '';
            my $c;
            while ($c = self.INFH.getc) ~~ /^\d$/ { $lines ~= $c }

            # Get cols
            my $cols = '';
            while ($c = self.INFH.getc) ~~ /^\d$/ { $cols ~= $c }

            if $lines ≠ '' and $cols ≠ '' {
                $rowsize = Int($lines);
                $colsize = Int($cols);

                last;
            }
        }

        # Reset terminal;
        $oldin.setattr(:DRAIN);

        self.INFH.encoding($oldenc);     # Restore encoding

        return $rowsize, $colsize;
    }

    method isatty(-->Bool) {
        return self.INFH.t;
    }

    # Indirectly tested
    method add-lock(-->Nil) {
        $.SEMAPHORE.protect: {
            if $!tasks.lock.get-lock {
                # We obtained the lock
                @!TASKS = Array.new;
                self.validate-dir();
            }
        };
        return;
    }

    # Indirectly tested
    method remove-lock(-->Nil) {
        $!tasks.lock.release-lock;
        return;
    }

    # For testing purposes
    method get-lock-count(-->Int:D) { $!tasks.lock.get-lock-count; }

    # Indirectly tested
    method validate-dir() {
        if ! $!tasks.data-dir.f {
            $!tasks.data-dir.mkdir;
        }

        return;
    }

    # Indirectly tested
    method validate-done-dir-exists() {
        self.validate-dir();
        my $done = $!tasks.data-dir.add("done");
        if ! $done.f {
            $done.mkdir;
        }

        return;
    }

    # Indirectly tested
    method pretty-day(Date:D $dt) {
        state @days = « unknown Mon Tue Wed Thu Fri Sat Sun »;
        state @months = « unknown Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec »;

        my $weekday = @days[$dt.day-of-week];
        my $month   = @months[$dt.month];
        my $day     = $dt.day.fmt("%2d");
        my $year    = $dt.year;

        return "$weekday $month $day 23:59:59 $year";
    }

    # Indirectly tested
    # Displays a number followed by either the word "day" or "days"
    sub in-days(Int() $days) {
        if $days == 1 {
            return "$days day";
        } else {
            return "$days days";
        }
    }

    sub ttyname(uint32) returns Str is native { * };

    my sub gettaskdir(-->IO::Path) {
        if %*ENV<TASKDIR>:exists { return %*ENV<TASKDIR>.IO }
        if %*ENV<HOME>:exists    { return %*ENV<HOME>.IO.add(".task") }
        return ".task".IO;
    }
}

