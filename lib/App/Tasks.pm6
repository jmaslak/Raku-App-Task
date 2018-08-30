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

    # Fix %*ENV<SHELL> so LESS doesn't give error messages
    if %*ENV<SHELL>:exists {
        if %*ENV<SHELL> eq '-bash' {
            %*ENV<SHELL> = 'bash';
        }
    }

    my %H_INFO = (
        title => {
            order   => 1,
            display => 'Title'
        },
        created => {
            order   => 2,
            display => 'Created',
            type    => 'date'
        }
    );

    my $H_LEN = %H_INFO.values.map( { .<display>.chars } ).max;

    method start(@args is copy) {
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
            when 'new' { self.task-new(|@args) }
            when 'add' { self.task-new(|@args) }
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
                    @args[0] = prompt(
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
            default {
                say "WRONG USAGE";
            }
        }
    }

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

    method get-task-filenames() {
        self.add-lock;
        my @ret = self.data-dir.dir(test => { m:s/^ \d+ '-' .* \.task $ / }).sort;
        self.remove-lock;

        return @ret;
    }

    method task-new() {
        self.add-lock;

        my $seq = self.get-next-sequence;

        my $subject = self.str-prompt( "$P1 Enter Task Subject $P2" ) or exit;
        $subject ~~ s/^\s+//;
        $subject ~~ s/\s+$//;
        $subject ~~ s:g/\t/ /;
        if ( $subject eq '' ) { say "Blank subject, exiting."; exit; }
        say "";

        my $body = self.get-note-from-user();

        if ! self.confirm-save() {
            say "Aborting.";
            self.remove-lock;
            exit;
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

        self.remove-lock();

        say "Created task $seq";
        return;
    }

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

    method read-task(Int $tasknum where * ~~ ^100_000) {
        self.add-lock();

        my $task = {};
        $task<header> = Hash.new;
        $task<body>   = [];
        $task<number> = $tasknum;

        my @lines = self.get-task-filename($tasknum).lines;
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
        if %H_INFO{$header}<type>:exists and %H_INFO{$header}<type> eq 'date' {
            $value = localtime($value, :scalar);
        }

        my $out = '';

        my $len = $H_LEN;

        $out ~= color("bold green");
        $out ~= sprintf( "%-{$len}s : ", %H_INFO{$header}<display> );
        $out ~= color("bold yellow");
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

    method task-add-note(Int $tasknum where * ~~ ^100_000) {
        self.add-lock();

        if ! self.check-task-log() {
            self.remove-lock();
            say "Can't add note - task numbers may have changed since last 'task list'";
            return;
        }

        self.add-note($tasknum);

        self.remove-lock();
    }

    method add-note(Int $tasknum where * ~~ ^100_000) {
        self.add-lock();

        self.task-show($tasknum);

        my $note = self.get-note-from-user();
        if ( !defined($note) ) {
            self.remove-lock();
            say "Not adding note";
            return;
        }

        if ! self.confirm-save() {
            self.remove-lock();
            say "Aborting.";
            exit;
        }

        my $fn = self.get-task-filename($tasknum) or die("Task not found");
        my $fh = $fn.open(:a);
        $fh.say: "--- " ~ time;
        $fh.say: $note;
        $fh.close;

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
        while defined my $line = $*IN.get {
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

    method task-close(Int $tasknum where * ~~ ^100_000) {
        self.add-lock();

        if ! self.check-task-log() {
            self.remove-lock();
            say "Can't close task - task numbers may have changed since last 'task list'";
            return;
        }

        self.add-note($tasknum);

        my $fn = self.get-task-filename($tasknum);
        my Str $taskstr = sprintf( "%05d", $tasknum );
        my ($meta) = $fn ~~ m/^ \d+ '-' (.*) '.task' $/;
        my $newfn = time.Str ~ "-$taskstr-$*PID-$meta.task";

        move $fn, "done/$newfn";
        say "Closed $taskstr";
        self.coalesce-tasks();

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

    method generate-task-list(Int $num? is copy where {!$num.defined or $num > 0}, $wchars?) {
        self.add-lock();

        my (@d) = self.get-task-filenames();
        my (@tasknums) = @d.map: { $^a.basename ~~ m/^ (\d+) /; Int($0) };

        my $out = '';
        for @tasknums.sort( { $^a <=> $^b } ) -> $tasknum {
            my $task = self.read-task($tasknum);

            my $title = $task<header><title>;
            my $desc  = $title;
            if ( defined($wchars) ) {
                $desc = substr( $title, 0, $wchars - $tasknum.chars - 1 );
            }
            $out ~= "$PINFOCOLOR$tasknum $PBOLDCOLOR$desc" ~ color('reset') ~ "\n";

            if defined($num) {

                # Exit the loop if we've displayed <num> entries
                $num--;
                if ( !$num ) { last; }
            }
        }

        self.remove-lock();

        return $out;
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

        for %elems.keys.sort -> $key {
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

    method yn-prompt($prompt --> Bool) {
        say "";
        while defined my $line = self.prompt($prompt) {
            $line = $line.fc();
            if $line eq '' {
                return True;
            } elsif $line ~~ m/ 'y' ( 'es' )? / {
                return True;
            } elsif $line ~~ m/ 'n' ( 'o' )? / {
                return False;
            }

            say "Invalid choice, please try again";
            say "";
        }

        return;
    }

    method prompt($prompt) {
        my $outprompt = $PCOLOR ~ $prompt ~ color('reset');
        return prompt $outprompt;
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
        my $oldenc = $*IN.encoding;
        $*IN.encoding('latin-1');       # Disable UTF processing

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
            while $*IN.getc.ord ≠ 27 { }
            if $*IN.getc ne '[' { next }

            # Okay, we have a CPR.
            # Get lines
            my $lines = '';
            my $c;
            while ($c = $*IN.getc) ~~ /^\d$/ { $lines ~= $c }

            # Get cols
            my $cols = '';
            while ($c = $*IN.getc) ~~ /^\d$/ { $cols ~= $c }

            if $lines ≠ '' and $cols ≠ '' {
                $rowsize = Int($lines);
                $colsize = Int($cols);

                last;
            }
        }

        # Reset terminal;
        $oldin.setattr(:DRAIN);

        $*IN.encoding($oldenc);     # Restore encoding

        return $rowsize, $colsize;
    }

    method isatty(-->Bool) {
        return $*IN.t;
    }

    method add-lock() {
        if $!LOCKCNT++ == 0 {
            self.validate-dir();

            $!LOCK = $.data-dir.add(".taskview.lock").open(:a);
            $!LOCK.lock;
        }

        return;
    }

    method remove-lock() {
        $!LOCKCNT--;
        if $!LOCKCNT < 0 {
            die("Cannot decrement lock");
        }
        if $!LOCKCNT == 0 {
            $!LOCK.unlock;
            $!LOCK.close;
        }

        return;
    }

    method validate-dir() {
        if ! $.data-dir.f {
            $.data-dir.mkdir;
        }

        return;
    }

    sub ttyname(uint32) returns Str is native { * };

}

