#
# Copyright (C) 2015-2018 Joelle Maslak
# All Rights Reserved
#
use v6;

class App::Tasks {
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

    my $PCOLOR     = color('reset bold cyan');
    my $PBOLDCOLOR = color('reset bold green');
    my $PINFOCOLOR = color('reset cyan');   # used to have dark

    my @PAGERCMD  = qw/less -RFX -P%PROMPT% -- %FILENAME%/;
    my @EDITORCMD = <nano -r 72 -s ispell +3,1 %FILENAME%>;

    has IO::Path $.data-dir = %*ENV<TASKDIR>:exists ?? %*ENV<TASKDIR>.IO !! $*PROGRAM.parent.add("data");

    has $!LOCK;
    has $.LOCKCNT = 0;
    has $.SEMAPHORE = Lock.new;
    has @!TASKS;

    # Partially implemented - there be dragons here!
    has $.write-output is rw = True; # Write output to terminal, used for testing only.

    has $.INFH  is rw = $*IN;   # Input Filehandle

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
            type         => 'string',
        },
        created => {
            order        => 2,
            display      => 'Created',
            type         => 'datetime',
        },
        expires => {
            order        => 3,
            display      => 'Expires',
            type         => 'day',
            alert-expire => True,
        },
    );

    my $H_LEN = %H_INFO.values.map( { .<display>.chars } ).max;

    method start(@args is copy, Bool :$expire-today? = False) {
        $*OUT.out-buffer = False;

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
                [ 'Quit to Shell',              'quit' ],
            );

            say "{$PCOLOR}Please select an option...\n";
            my $command = self.menu-prompt("$P1 $P2", @choices);
            @args.push($command // 'quit');

            if ( @args[0] eq 'quit' ) { exit; }
        }

        if @args.elems == 1 {
            if @args[0] ~~ m:s/^ \d+ $/ {
                @args.unshift: 'view';      # We view the task if one arg entered
            }
        }

        my @validtasks = self.get-task-filenames().map( { Int( S/\- .* $// ); } );

        my $cmd = @args.shift.fc;
        given $cmd {
            when $_ eq 'new' or $_ eq 'add' {
                if $expire-today {
                    my $old = $!check-freshness;
                    $!check-freshness = False;
                    self.task-new-expire-today(|@args);
                    $!check-freshness = $old;
                } else {
                    self.task-new(|@args);
                }
            }
            when 'move' {
                if @args[0]:!exists {
                    @args[0] = self.no-menu-prompt(
                        "$P1 Please enter source task number to move $P2",
                        @validtasks
                    ) or exit;
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
                    ) or exit;
                    say "";
                }
                self.task-show(|@args);
            }
            when 'note' {
                if @args[0]:!exists {
                    @args[0] = self.no-menu-prompt(
                        "$P1 Please enter task number to modify $P2",
                        @validtasks
                    ) or exit;
                    say "";
                }
                self.task-add-note(|@args);
            }
            when $_ ~~ 'close' or $_ ~~ 'commit' {
                if @args[0]:!exists {
                    @args[0] = self.prompt(
                        "$P1 Please enter task number to close $P2",
                        [@validtasks]
                    ) or exit;
                    say "";
                }
                self.task-close(|@args);
            }
            when 'list' { self.task-list(|@args) }
            when 'monitor' { self.task-monitor(|@args) }
            when 'coalesce' { self.task-coalesce(|@args) }
            when 'retitle' { self.task-retitle(|@args) }
            when 'set-expire' { self.task-set-expiration(|@args) }
            when 'expire' { self.expire(|@args) }
            default {
                say "WRONG USAGE";
            }
        }
    }

    # Has test
    method get-next-sequence() {
        self.add-lock();
        my @d = self.get-task-filenames();

        my $seq = 1;
        if @d.elems {
            $seq = pop(@d).basename;
            $seq ~~ s/ '-' .* $//;
            $seq++;
        }
        self.remove-lock();

        return sprintf "%05d", $seq;
    }

    # Indirectly tested
    method get-task-filenames() {
        self.add-lock;
        my @out = self.data-dir.dir(test => { m:s/^ \d+ '-' .* \.task $ / }).sort;
        self.remove-lock;

        return @out;
    }

    # Has task
    method task-new-expire-today(Str $sub?) {
        self.add-lock;

        my $task = self.task-new($sub);
        self.task-set-expiration($task.Int, Date.today.Str);

        self.remove-lock;
        return $task;
    }

    # Has test
    method task-new(Str $sub?) {
        self.add-lock;

        my $seq = self.get-next-sequence;

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
                self.remove-lock;
                exit;
            }
        }

        my $tm = time.Str;
        my $fh = self.data-dir.add("{$seq}-none.task").IO.open :w;
        $fh.say: "Title: $subject";
        $fh.say: "Created: $tm";

        if ( defined($body) ) {
            $fh.say: "--- $tm";
            $fh.print: $body;
        }

        $fh.close;

        @!TASKS = Array.new;    # Clear cache

        self.remove-lock();

        say "Created task $seq";
        return $seq;
    }

    # Indirectly tested
    method get-task-filename(Int $taskint where * ~~ ^100_000 --> IO::Path:D) {
        self.add-lock();

        my Str $task = sprintf( "%05d", $taskint );

        my @d = self.get-task-filenames();
        my @fn = @d.grep: { .basename ~~ m/^ $task '-'/ };

        if @fn.elems > 1  { self.remove-lock(); die "More than one name matches\n"; }
        if @fn.elems == 1 { self.remove-lock(); return @fn[0]; }

        self.remove-lock();
        return;
    }

    # Tested
    method task-move(Int $old where * ~~ ^100_000, Int $new where * ~~ ^100_000) {
        self.add-lock();

        if ! self.check-task-log() {
            self.remove-lock();
            say "Can't move task - task numbers may have changed since last 'task list'";
            return;
        }

        my $end = self.get-next-sequence();
        if ( $new >= $end ) {
            $new = $end - 1;
        }
        if ( $new < 1 ) { $new = 1; }

        my $oldfn = self.get-task-filename($old) or die("Task not found");

        my $oldbase = $oldfn.basename;
        my $newbase = S/^ \d+ '-'/-/ given $oldbase;
        my $newfn = $oldfn.parent.add: sprintf( "%05d%s", $new, $newbase);

        my $newfntmp = $oldfn.parent.add: $newfn.basename ~ '.tmp';

        move $oldfn, $newfntmp;

        my @d = self.get-task-filenames();

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

        self.remove-lock();
    }

    method task-show(Int $tasknum where * ~~ ^100_000) {
        self.add-lock();

        my $task = self.read-task($tasknum);

        my $out    = '';
        my $header = $task<header>;
        for %H_INFO.keys.sort( { %H_INFO{$^a}<order> <=> %H_INFO{$^b}<order> } ) -> $key {
            if $header{$key}:exists {
                $out ~= self.sprint-header-line( $key, $header{$key} );
            }
        }
        $out ~= "\n";

        for |$task<body> -> $body {
            $out ~= self.sprint-body($body);
            $out ~= "\n";
        }

        self.remove-lock();

        self.display-with-pager( "Task $tasknum", $out );
    }

    # Indirectly tested
    method read-task(Int $tasknum where * ~~ ^100_000) {
        self.add-lock();

        my $task = {};
        $task<header>   = Hash.new;
        $task<body>     = [];
        $task<number>   = $tasknum;
        $task<expire>   = Date;   # Empty object
        $task<filename> = self.get-task-filename($tasknum);

        my @lines = $task<filename>.lines;
        while (@lines) {
            my $line = @lines.shift;

            if ( $line ~~ m/^ '--- ' \d+ $/ ) {
                @lines.unshift: "$line";
                self.read-task-body( $task, @lines );
                @lines = ();
                next;
            }

            # We know we are in the header.
            $line ~~ /^ ( <-[:]> + ) ':' \s* ( .* ) \s* $/;
            my ($field, $value) = @();

            $task<header>{ $field.Str.fc } = $value.Str;
        }

        self.remove-lock();

        return $task;
    }

    # Indirectly tested
    method write-task(Int $tasknum where * ~~ ^100_000, %task) {
        self.add-lock;

        my $fn = self.get-task-filename($tasknum) or die("Task not found");

        my $fh = $fn.open(:w);

        for %task<header>.kv -> $key, $val {
            if ! $val.defined { next; }

            $fh.say: "$key: $val";
        }

        for %task<body>.list -> $note {
            $fh.say: "--- $note<date>";
            $fh.print: $note<body>;
            if $note<body> !~~ m:s/ \n $/ {
                $fh.say: "";
            }
        }

        $fh.close;
        
        @!TASKS = Array.new;    # Clear cache

        self.remove-lock;
    }

    # Indirectly tested
    method read-task-body(Hash $task is rw, @lines) {
        self.add-lock();

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

        self.remove-lock();
    }

    method sprint-header-line($header, $value is copy) {
        my $alert = False;
        if %H_INFO{$header}<type>:exists and %H_INFO{$header}<type> eq 'datetime' {
            $value = localtime($value, :scalar);
        }
        if %H_INFO{$header}<type>:exists and %H_INFO{$header}<type> eq 'day' {
            my $parsed = self.pretty-day($value);
            if %H_INFO{$header}<alert-expire>:exists and %H_INFO{$header}<alert-expire> {
                if Date.new($value) < Date.today {
                    $alert = True;
                    $parsed = "$value (expired)";
                }
            }
            $value = $parsed;
        }

        my $out = '';

        my $len = $H_LEN;

        $out ~= color("bold green");
        $out ~= sprintf( "%-{$len}s : ", %H_INFO{$header}<display> );
        if $alert {
            $out ~= color("bold red");
        } else {
            $out ~= color("bold yellow");
        }
        $out ~= $value;
        $out ~= color("reset");
        $out ~= "\n";

        return $out;
    }

    method sprint-body($body) {
        my $out =
            color("bold red") ~ "["
        ~ localtime($body<date>, :scalar) ~ "]"
        ~ color('reset')
        ~ color('red') ~ ':'
        ~ color("reset") ~ "\n";

        my $coloredtext = $body<body>;
        my $yellow      = color("yellow");
        $coloredtext   ~~ s:g/^^/$yellow/;

        $out ~= $coloredtext ~ color("reset");

        return $out;
    }

    # Tested
    method task-retitle(Int $tasknum? where { !$tasknum.defined or $tasknum > 0 }, Str $newtitle? is copy) {
        self.add-lock();

        if ! self.check-task-log() {
            self.remove-lock();
            say "Can't retitle - task numbers may have changed since last 'task list'";
            return;
        }

        if !$tasknum.defined {
            my @d = self.get-task-filenames();
            my (@validtasks) = @d.map: { $^a.basename ~~ m/^ (\d+) /; Int($0) };

            $tasknum = self.no-menu-prompt(
                "$P1 Please enter task number to modify $P2",
                @validtasks
            ) or exit;
        }

        if !$newtitle.defined or $newtitle eq '' {
            $newtitle = self.str-prompt("$P1 Please enter the new title $P2");
        }

        self.retitle($tasknum, $newtitle);

        self.remove-lock;
    }

    # Indirectly tested
    method retitle(Int $tasknum where * ~~ ^100_000, Str:D $newtitle) {
        self.add-lock;

        my $fn = self.get-task-filename($tasknum) or die("Task not found");
        my $oldtask = self.read-task($tasknum);

        my @lines = $fn.lines();
        for @lines -> $line is rw {
            if $line ~~ m/^Title: / {
                $line = "Title: $newtitle";
                last;
            }
        }
        $fn.spurt(@lines.join("\n") ~ "\n");

        self.add-note(
            $tasknum,
            "Title changed from:\n" ~
                "  " ~ $oldtask<header><title> ~ "\n" ~
                "To:\n" ~
                "  " ~ $newtitle
        );

        @!TASKS = Array.new;    # Clear cache

        self.remove-lock;
    }

    # Tested
    method expire() {
        self.add-lock();

        my @tasks = self.read-tasks();
        for @tasks -> $task {
            if $task<header><expires>:exists {
                if Date.new($task<header><expires>) < Date.today {
                    self.add-note($task<number>, "Task expired, closed.");
                    self.task-close($task<number>, :coalesce(False), :interactive(False));
                }
            }
        }
        self.coalesce-tasks();

        @!TASKS = Array.new;
        self.remove-lock;
    }

    # Tested
    method task-set-expiration(Int $tasknum? is copy where { !$tasknum.defined or $tasknum > 0 }, Str $day? is copy) {
        self.add-lock();

        if $day.defined {
            if $day !~~ m/^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/ {
                say "Invalid date format - please use YYYY-MM-DD format";
                self.remove-lock;
                return;
            }
        }

        if ! self.check-task-log() {
            self.remove-lock();
            say "Can't set expiration - task numbers may have changed since last 'task list'";
            return;
        }

        if !$tasknum.defined {
            my @d = self.get-task-filenames();
            my (@validtasks) = @d.map: { $^a.basename ~~ m/^ (\d+) /; Int($0) };

            my $tn = self.no-menu-prompt(
                "$P1 Please enter task number to modify $P2",
                @validtasks
            ) or exit;
            $tasknum = $tn.Int;
        }

        while !$day.defined or $day eq '' {
            $day = self.str-prompt("$P1 Please enter the last valid day for this task $P2");
            if $day !~~ m/^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/ {
                say "Date format is incorrect\n";
                $day = '';
            }
        }

        my $now    = Date.today;
        my $expire = Date.new($day);

        if $expire < $now {
            say "Date cannot be before today";
            self.remove-lock;
            return;
        }

        self.set-expiration($tasknum, $expire);

        self.remove-lock;
    }

    # Indirectly tested
    method set-expiration(Int $tasknum where * ~~ ^100_000, Date:D $day) {
        self.add-lock;

        my $fn = self.get-task-filename($tasknum) or die("Task not found");
        my $oldtask = self.read-task($tasknum);

        my $added = False;

        my @lines = $fn.lines();
        # XXX We should build a better way of modifying the headers.
        for @lines -> $line is rw {
            if $oldtask<header><expires>:exists {
                if $line ~~ m/^Expires: / {
                    $line    = "Expires: $day";
                    $added   = True;
                    last;
                }
            } else {
                if $line ~~ m/^Created: / {
                    $line = "$line\nExpires: $day";
                }
            }
        }
        $fn.spurt(@lines.join("\n") ~ "\n");

        if $oldtask<header><expires>:exists {
            self.add-note(
                $tasknum,
                "Updated expiration date from " ~
                    $oldtask<header><expires> ~
                    " to $day"
            );
        } else {
            self.add-note( $tasknum, "Added expiration date: " ~ $day );
        }

        @!TASKS = Array.new;    # Clear cache

        self.remove-lock;
    }

    # Tested
    method task-add-note(Int $tasknum where * ~~ ^100_000, Str $note?) {
        self.add-lock();

        if ! self.check-task-log() {
            self.remove-lock();
            say "Can't add note - task numbers may have changed since last 'task list'";
            return;
        }

        self.add-note($tasknum, $note);

        self.remove-lock();
    }

    # Indirectly tested
    method add-note(Int $tasknum where * ~~ ^100_000, Str $orignote?) {
        self.add-lock();

        if ! $orignote.defined {
            self.task-show($tasknum);
        }

        my $note = $orignote;
        if !$note.defined {
            $note = self.get-note-from-user();
        }

        if ( !defined($note) ) {
            self.remove-lock();
            say "Not adding note";
            return;
        }

        if ! $orignote.defined and ! self.confirm-save() {
            self.remove-lock();
            say "Aborting.";
            exit;
        }

        my $task = self.read-task($tasknum);

        my %note;
        %note<date> = time;
        %note<body> = $note;
        $task<body>.push: %note;

        self.write-task($tasknum, $task);

        self.remove-lock();

        say "Updated task $tasknum";
    }

    method confirm-save() {
        my $result = self.yn-prompt(
            "$P1 Save This Task [Y/n]? $P2"
        );
        return $result;
    }

    method get-note-from-user() {
        if ! @EDITORCMD {
            return self.get-note-from-user-internal();
        } else {
            return self.get-note-from-user-external();
        }
    }

    method get-note-from-user-internal() {
        print color("bold cyan") ~ "Enter Note Details" ~ color("reset");
        say color("cyan")
        ~ " (Use '.' on a line by itself when done)"
        ~ color("bold cyan") ~ ":"
        ~ color("reset");

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

        my @cmd = map { S:g/'%FILENAME%'/$filename/ }, @EDITORCMD;
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
        self.add-lock();

        if $interactive and ! self.check-task-log() {
            self.remove-lock();
            say "Can't close task - task numbers may have changed since last 'task list'";
            return;
        }

        if $interactive {
            self.add-note($tasknum);
        }

        my $fn = self.get-task-filename($tasknum);
        my Str $taskstr = sprintf( "%05d", $tasknum );
        $fn.basename ~~ m/^ \d+ '-' (.*) '.task' $/;
        my ($meta) = $0;
        my $newfn = time.Str ~ "-$taskstr-$*PID-$meta.task";

        self.validate-done-dir-exists();

        my $newpath = $.data-dir.add("done").add($newfn);
        move $fn, $newpath;
        say "Closed $taskstr";

        @!TASKS = Array.new;
        if $coalesce {
            self.coalesce-tasks();
        }

        self.remove-lock();
    }

    # XXX Need a non-colorized option
    method display-with-pager($description, $contents) {
        if @PAGERCMD.elems {
            my ($filename, $tmp) = tempfile(:unlink);
            $tmp.print: $contents;
            $tmp.close;

            my $out = "$description ( press h for help or q to quit ) ";

            my @pager;
            for @PAGERCMD -> $part is copy {
                $part ~~ s:g/'%PROMPT%'/$out/;
                $part ~~ s:g/'%FILENAME%'/$filename/;
                @pager.push: $part;
            }
            run(@pager);
        } else {
            print $contents;
        }
    }

    # Tested
    method read-tasks(Int $num? is copy where { !$num.defined or $num > 0}) {
        self.add-lock;
        if @!TASKS.elems {
            self.remove-lock;
            return @!TASKS;
        };

        my (@d)        = self.get-task-filenames();
        my (@tasknums) = @d.map: { $^a.basename ~~ m/^ (\d+) /; Int($0) };
        @tasknums = @tasknums.sort( { $^a <=> $^b } ).list;

        my $taskcnt = min(@tasknums.elems, $num ?? $num !! @tasknums.elems);

        my %out;
        race for @tasknums.race(batch => 1, degree => 16) -> $tasknum {
            %out{$tasknum} = self.read-task($tasknum);
        }

        @!TASKS = %out.keys.sort( { $^a <=> $^b } ).map: { %out{$^a} };
        self.remove-lock;
        return @!TASKS;
    }

    method generate-task-list(Int $num? is copy where {!$num.defined or $num > 0}, $wchars?) {
        self.add-lock();

        my @tasks = self.read-tasks($num);

        my Int $maxnum = @tasks.map({ $^a<number>}).max;

        my @out = @tasks.hyper.map: -> $task {
            my $title = $task<header><title>;
            my $desc  = $title;
            if ( defined($wchars) ) {
                $desc = substr( $title, 0, $wchars - $maxnum.chars - 1 );
            }

            "$PINFOCOLOR$task<number> $PBOLDCOLOR$desc" ~ color('reset') ~ "\n"
        };

        self.remove-lock();

        return @out.join();
    }

    method task-list(Int $num? where { !$num.defined or $num > 0 }) {
        self.add-lock();

        self.update-task-log();    # So we know we've done this.
        my $out = self.generate-task-list( $num, Nil );

        self.display-with-pager( "Tasklist", $out );

        self.remove-lock();
    }

    method task-monitor() {
        self.task-monitor-show();

        react {
            whenever key-pressed(:!echo) {
                say color("reset");
                say "";
                say "Exiting.";
                done;
            }
            whenever Supply.interval(1) {
                self.task-monitor-show();
            }
        }
    }

    method task-monitor-show() {
        self.add-lock();

        state $last = 'x';  # Not '' because then we won't try to draw the initial
                            # screen - there will be no "type any character" prompt!

        state ($rows, $cols) = self.get-size();
        if ($last = 'x') {
            if !defined $cols { die "Terminal not supported" }

            self.update-task-log();    # So we know we've done this.
        }

        my $out = localtime(:scalar) ~ ' local / ' ~ gmtime(:scalar) ~ " UTC\n\n";

        $out ~= self.generate-task-list( $rows - 3, $cols - 1 );
        if $out ne $last {
            $last = $out;
            self.clear;
            print $out;
            print color("reset");
            print "     ...Type any character to exit...  ";
        }

        self.remove-lock();
    }

    method task-coalesce() {
        self.add-lock();

        self.coalesce-tasks();

        self.remove-lock();

        say "Coalesced tasks";
    }

    method coalesce-tasks() {
        self.add-lock();

        my @nums = self.get-task-filenames().map: { S/'-' .* .* '.task' $// given .basename };

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

        self.remove-lock();
    }

    method update-task-log() {
        self.add-lock();

        my $sha = self.get-taskhash();

        my @terms;
        my $status = $.data-dir.add(".taskview.status");
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
                self.remove-lock();
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

        self.remove-lock();
    }

    # Returns true if the task log is okay for this process.
    method check-task-log() {
        # Not a TTY?  Don't worry about this.
        if ! self.isatty() { return 1; }

        # Skip freshness check?
        if ! $!check-freshness { return 1; }

        self.add-lock();

        my $sha = self.get-taskhash();

        my $status = $.data-dir.add(".taskview.status");

        my @terms;
        if $status.f {
            @terms = $status.lines;
        }

        my $oldhash = '';
        if @terms {
            $oldhash = @terms.shift;
        }

        # If hashes differ, it's not cool.
        if ( $oldhash ne $sha ) { self.remove-lock(); return; }

        # If terminal in list, it's cool.
        my $tty = self.get-ttyname();
        if @terms.grep( { $^a eq $tty } ) {
            self.remove-lock();
            return 1;
        }

        self.remove-lock();

        # Not in list.
        return;
    }

    method get-taskhash() {
        self.add-lock();
        my $tl = self.generate-task-list( Int, Int );
        self.remove-lock();

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

            printf "{$PBOLDCOLOR}%{$width}d.{$PINFOCOLOR} %s\n", $key, $elem<description>;
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
            if $line !~~ m:s/ ^ \d+ $ / {
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
        my $outprompt = $PCOLOR ~ $prompt ~ color('reset');
        print $outprompt if $.write-output;
        return $.INFH.get;
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
    method add-lock() {
        $.SEMAPHORE.protect( {
            if $!LOCKCNT++ == 0 {
                @!TASKS = Array.new;
                self.validate-dir();

                $!LOCK = $.data-dir.add(".taskview.lock").open(:a);
                $!LOCK.lock;
            }

            if $!LOCKCNT > 80 { die("Lock leak detected!"); }
        } );

        return;
    }

    # Indirectly tested
    method remove-lock() {
        $.SEMAPHORE.protect( {
            $!LOCKCNT--;
            if $!LOCKCNT < 0 {
                die("Cannot decrement lock");
            }
            if $!LOCKCNT == 0 {
                $!LOCK.unlock;
                $!LOCK.close;
            }
        } );

        return;
    }

    # Indirectly tested
    method validate-dir() {
        if ! $.data-dir.f {
            $.data-dir.mkdir;
        }

        return;
    }

    # Indirectly tested
    method validate-done-dir-exists() {
        self.validate-dir();
        my $done = $.data-dir.add("done");
        if ! $done.f {
            $done.mkdir;
        }

        return;
    }

    # Indirectly tested
    method pretty-day(Str:D $raw where /^ <[0..9]>**4 '-' <[0..9]><[0..9]> '-' <[0..9]><[0..9]> $/) {
        my $dt = Date.new($raw);

        state @days = « unknown Mon Tue Wed Thu Fri Sat Sun »;
        state @months = « unknown Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec »;

        my $weekday = @days[$dt.day-of-week];
        my $month   = @months[$dt.month];
        my $day     = $dt.day.fmt("%2d");
        my $year    = $dt.year;

        return "$weekday $month $day 23:59:59 $year";
    }

    sub ttyname(uint32) returns Str is native { * };

}

