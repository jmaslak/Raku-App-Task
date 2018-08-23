#
# Copyright (C) 2015-2018 Joelle Maslak
# All Rights Reserved
#

package App::Tasks;

use strict;
use warnings;

use v5.10;

use Carp;
use File::Copy;
use File::Slurp;
use File::Temp;
use FindBin;
use IO::Dir;
use IO::Prompter;
use List::Util qw/max/;
use Term::ANSIColor;    # Used for IO::Prompter to do color
use Term::Cap;
use Term::ReadKey;

my $P1         = '[task]';
my $P2         = '> ';
my $PCOLOR     = color('reset bold cyan');
my $PBOLDCOLOR = color('reset bold green');
my $PINFOCOLOR = color('reset dark cyan');
my @PSTYLE     = (
    -style => "reset bold cyan"

      # -echostyle => "bold cyan"
);

my @PAGERCMD = qw/less -RFX -P%PROMPT% -- %FILENAME%/;
my @EDITORCMD;
{
    no warnings 'qw';    # disable comma warning
    @EDITORCMD = qw/nano -r 72 -s ispell +3,1 %FILENAME%/;
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

my $H_LEN = max( map { length( $_->{display} ) } values %H_INFO );

sub start {
    my (@args) = @_;

    chdir "$FindBin::Bin/data";
    $| = 1;

    if ( scalar(@args) < 1 ) {

        my @choices = (
            { 'Create New Task'            => 'new' },
            { 'Add a Note to a Task'       => 'note' },
            { 'View an Existing Task'      => 'show' },
            { 'List All Tasks'             => 'list' },
            { 'Monitor Task List'          => 'monitor' },
            { 'Move (Reprioritize) a Task' => 'move' },
            { 'Close a Task'               => 'close' },
            { 'Coalesce Tasks'             => 'coalesce' },
            { 'Quit to Shell'              => 'quit' }
        );

        say "${PCOLOR}Please select an option...\n";
        say "\n";
        for ( my $i = 1; $i <= scalar(@choices); $i++ ) {
            printf "${PBOLDCOLOR}%2d.${PINFOCOLOR} %s\n", $i, keys %{ $choices[ $i - 1 ] };
        }
        say "";

        my $command = prompt(
            -integer => sub { $_ > 0 && $_ <= scalar(@choices); },
            @PSTYLE,
            "$P1 $P2"
        ) || 'quit';

        my (@tmp) = values %{ $choices[ $command - 1 ] };
        $args[0] = $tmp[0];
        say "";

        if ( $args[0] eq 'quit' ) { exit; }
    }

    if ( scalar(@args) == 1 ) {
        if ( $args[0] =~ /^\d+$/ ) {
            unshift @args, 'view';    # We view the task if one arg entered
        }
    }

    my @validtasks = map { s/-.*$//; int($_); } get_task_filenames();

    my $cmd = lc( shift(@args) );
    if ( ( $cmd eq 'new' ) or ( $cmd eq 'add' ) ) {
        task_new(@args);
    } elsif ( $cmd eq 'move' ) {
        if ( !defined( $args[0] ) ) {
            $args[0] = prompt(
                "$P1 Please enter source task number to move $P2",
                -integer   => sub { $_ > 0 },
                -guarantee => [@validtasks],
                @PSTYLE
            ) or exit;
        }
        if ( !defined( $args[1] ) ) {
            $args[1] = prompt(
                "$P1 Please enter desired location of task $P2",
                -integer => sub { $_ > 0 },
                @PSTYLE
            ) or exit;
        }
        task_move(@args);
    } elsif ( ( $cmd eq 'show' ) or ( $cmd eq 'view' ) ) {
        if ( !defined( $args[0] ) ) {
            $args[0] = prompt(
                "$P1 Please enter task number to show $P2",
                -integer   => sub { $_ > 0 },
                -guarantee => [@validtasks],
                @PSTYLE
            ) or exit;
            say "";
        }
        task_show(@args);
    } elsif ( $cmd eq 'note' ) {
        if ( !defined( $args[0] ) ) {
            $args[0] = prompt(
                "$P1 Please enter task number to modify $P2",
                -integer   => sub { $_ > 0 },
                -guarantee => [@validtasks],
                @PSTYLE
            ) or exit;
            say "";
        }
        task_add_note(@args);
    } elsif ( ( $cmd eq 'close' ) or ( $cmd eq 'commit' ) ) {
        if ( !defined( $args[0] ) ) {
            $args[0] = prompt(
                "$P1 Please enter task number to close $P2",
                -integer   => sub { $_ > 0 },
                -guarantee => [@validtasks],
                @PSTYLE
            ) or exit;
            say "";
        }
        task_close(@args);
    } elsif ( $cmd eq 'list' ) {
        task_list(@args);
    } elsif ( $cmd eq 'monitor' ) {
        task_monitor(@args);
    } elsif ( $cmd eq 'coalesce' ) {
        task_coalesce(@args);
    } else {
        say "WRONG USAGE";
    }
}

sub get_next_sequence {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    my @d = get_task_filenames();

    my $seq = 1;
    if ( scalar(@d) != 0 ) {
        $seq = pop(@d);
        $seq =~ s/-.*$//;
        $seq++;
    }

    return sprintf "%05d", $seq;
}

sub get_task_filenames {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    tie my %dir, 'IO::Dir', '.';
    return sort grep { /^\d+-.*\.task$/ } keys %dir;
}

sub task_new {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    my $seq = get_next_sequence;

    my $subject = prompt( "$P1 Enter Task Subject $P2", @PSTYLE ) or exit;
    $subject =~ s/^\s+//o;
    $subject =~ s/\s+$/o/;
    $subject =~ s/\t/ /og;
    if ( $subject eq '' ) { say "Blank subject, exiting."; exit; }
    say "";

    my $body = get_note_from_user();

    if ( !confirm_save() ) {
        say "Aborting.";
        exit;
    }

    my $tm = scalar( time() );
    open my $fh, '>', "$seq-none.task";
    say $fh "Title: $subject";
    say $fh "Created: $tm";

    if ( defined($body) ) {
        say $fh "--- $tm";
        print $fh $body;
    }

    close $fh;

    say "Created task $seq";
}

sub get_task_filename {
    if ( scalar(@_) != 1 ) { confess 'invalid call' }
    my ($task) = @_;

    $task = sprintf( "%05d", $task );

    my @d = get_task_filenames();
    my @fn = grep { /^$task-/ } @d;

    if ( scalar(@fn) > 1 )  { die "More than one name matches\n"; }
    if ( scalar(@fn) == 1 ) { return $fn[0]; }
    return undef;
}

sub task_move {
    if ( scalar(@_) != 2 ) { confess 'invalid call' }
    my ( $old, $new ) = @_;

    my $end = get_next_sequence();
    if ( $new >= $end ) {
        $new = $end - 1;
    }
    if ( $new < 1 ) { $new = 1; }

    my $oldfn = get_task_filename($old) or die("Task not found");
    my $newfn = $oldfn;
    $newfn =~ s/^\d+-/-/;
    $newfn = sprintf( "%05d%s", $new, $newfn );

    move $oldfn, "$newfn.tmp";

    my @d = get_task_filenames();

    if ( $new < $old ) { @d = reverse @d; }
    foreach my $f (@d) {
        my $num = $f;
        $num =~ s/-.*$//;
        if ( $num == $old ) {

            # Skip the file that isn't there anymore
            next;
        }

        my $suffix = $f;
        $suffix =~ s/^\d+-/-/;

        if ( $new < $old ) {
            if ( ( $num >= $new ) && ( $num <= $old ) ) {
                $num = sprintf( "%05d", $num + 1 );
                move $f, "$num$suffix";
            }
        } elsif ( $new > $old ) {
            if ( ( $num <= $new ) && ( $num >= $old ) ) {
                $num = sprintf( "%05d", $num - 1 );
                move $f, "$num$suffix";
            }
        }
    }

    move "$newfn.tmp", $newfn;

}

sub task_show {
    if ( scalar(@_) != 1 ) { confess 'invalid call' }
    my ($tasknum) = @_;

    my $task = read_task($tasknum);

    my $out    = '';
    my $header = $task->{header};
    for my $key (
        sort { $H_INFO{$a}->{order} <=> $H_INFO{$b}->{order} }
        keys %H_INFO
      )
    {
        if ( exists( $header->{$key} ) ) {
            $out .= sprint_header_line( $key, $header->{$key} );
        }
    }
    $out .= "\n";

    for my $body ( @{ $task->{body} } ) {
        $out .= sprint_body($body);
        $out .= "\n";
    }

    display_with_pager( "Task $tasknum", $out );
}

sub read_task {
    if ( scalar(@_) != 1 ) { confess 'invalid call' }
    my ($tasknum) = @_;

    my $task = {};
    $task->{header} = {};
    $task->{body}   = [];
    $task->{number} = $tasknum;

    my @lines = File::Slurp::read_file( get_task_filename($tasknum) );
    while (@lines) {
        my $line = shift(@lines);
        chomp($line);

        if ( $line =~ /^--- \d+$/ ) {
            unshift @lines, "$line\n";
            read_task_body( $task, \@lines );
            next;
        }

        # We know we are in the header.
        my ( $field, $value ) = $line =~ /^([^:]+):\s*(.*$)\s*$/;
        $task->{header}{ lc($field) } = $value;
    }

    return $task;
}

sub read_task_body {
    if ( scalar(@_) != 2 ) { confess 'invalid call' }
    my ( $task, $lines ) = @_;

    while (@$lines) {
        my $line = shift(@$lines);
        chomp($line);

        if ( $line =~ /^--- \d+$/ ) {
            my ($bodydate) = $line =~ /^--- (\d+)$/;
            my $body = {};
            $body->{date} = $bodydate;
            $body->{body} = '';

            push @{ $task->{body} }, $body;
            next;
        }

        $task->{body}->[-1]->{body} .= $line . "\n";
    }
}

sub sprint_header_line {
    if ( scalar(@_) != 2 ) { confess 'invalid call' }
    my ( $header, $value ) = @_;

    if ( exists( $H_INFO{$header}->{type} )
        && ( $H_INFO{$header}->{type} eq 'date' ) )
    {
        $value = scalar( localtime($value) );
    }

    my $out = '';

    my $len = $H_LEN;
    $out .=
      sprintf(
        color("bold green") . "%-${len}s : " . color("bold yellow") . "%s" . color("reset") . "\n",
        $H_INFO{$header}{display}, $value );

    return $out;
}

sub sprint_body {
    if ( scalar(@_) != 1 ) { confess 'invalid call'; }
    my ($body) = @_;

    my $out =
        color("bold red") . "["
      . scalar( localtime $body->{date} ) . "]"
      . color('reset')
      . color('red') . ':'
      . color("reset") . "\n";

    my $coloredtext = $body->{body};
    my $yellow      = color("yellow");
    $coloredtext =~ s/^/$yellow/mg;
    $out .= $coloredtext . color("reset");

    return $out;
}

sub task_add_note {
    if ( scalar(@_) != 1 ) { confess 'invalid call'; }
    my ($tasknum) = @_;

    add_note($tasknum);
}

sub add_note {
    if ( scalar(@_) != 1 ) { confess 'invalid call'; }
    my ($tasknum) = @_;

    task_show($tasknum);

    my $note = get_note_from_user();
    if ( !defined($note) ) {
        say "Not adding note";
        return;
    }

    if ( !( confirm_save() ) ) {
        say "Aborting.";
        exit;
    }

    my $fn = get_task_filename($tasknum) or die("Task not found");
    write_file( $fn, { append => 1 }, "--- " . time() . "\n$note" );

    say "Updated task $tasknum";
}

sub confirm_save {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    my $result = prompt(
        "$P1 Save This Task [Y/n]? $P2",
        -yn,
        -single,
        -default => 'y',
        @PSTYLE
    );
    return $result;
}

sub get_note_from_user {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    if ( scalar(@EDITORCMD) == 0 ) {
        return get_note_from_user_internal();
    } else {
        return get_note_from_user_external();
    }
}

sub get_note_from_user_internal {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    print color("bold cyan") . "Enter Note Details" . color("reset");
    print color("cyan")
      . " (Use '.' on a line by itself when done)"
      . color("bold cyan") . ":"
      . color("reset") . "\n";

    my $body = '';
    while (1) {
        my $line = <STDIN>;
        chomp $line;
        if ( $line eq '.' ) {
            last;
        }
        $body .= $line . "\n";
    }

    say "";

    if ( $body eq '' ) {
        return;
    }

    return $body;
}

sub get_note_from_user_external {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    # External editors may pop up full screen, so you won't see any
    # history.  This helps mitigate that.
    my $result = prompt(
        "$P1 Add a Note to This Task [Y/n]? $P2",
        -yn,
        -single,
        -default => 'y',
        @PSTYLE
    );

    if ( !$result ) {
        return;
    }

    my $prompt = "Please enter any notes that should appear " . "for this task below this line.";

    my $tmp      = File::Temp->new();
    my $filename = $tmp->filename;
    say $tmp $prompt;
    say $tmp '-' x 72;
    close $tmp;

    my @cmd = map { s/%FILENAME%/$filename/g; $_ } @EDITORCMD;
    system(@cmd);

    my @lines = File::Slurp::read_file($filename);
    if ( !scalar(@lines) ) { return; }

    # Eat the header
    my $first = $lines[0];
    chomp $first;
    if ( $first eq $prompt ) { shift @lines; }
    if ( scalar(@lines) ) {
        my $second = $lines[0];
        chomp($second);
        if ( $second eq '-' x 72 ) { shift @lines; }
    }

    # Remove blank lines at top
    while ( scalar(@lines) ) {
        my $line = $lines[0];
        chomp $line;

        if ( $line eq '' ) {
            shift @lines;
        } else {
            last;
        }
    }

    # Remove blank lines at bottom
    while ( scalar(@lines) ) {
        my $line = $lines[-1];
        chomp $line;

        if ( $line eq '' ) {
            pop @lines;
        } else {
            last;
        }
    }

    my $out = join '', @lines;
    if ( $out ne '' ) {
        return $out;
    } else {
        return;
    }
}

sub task_close {
    if ( scalar(@_) != 1 ) { confess 'invalid call'; }
    my ($tasknum) = @_;

    add_note($tasknum);

    my $fn = get_task_filename($tasknum);
    $tasknum = sprintf( "%05d", $tasknum );
    my ($meta) = $fn =~ /^\d+-(.*).task$/;
    my $newfn = scalar(time) . "-$tasknum-$$-$meta.task";

    move $fn, "done/$newfn";
    say "Closed $tasknum";
    coalesce_tasks();
}

# XXX Need a non-colorized option
sub display_with_pager {
    if ( scalar(@_) != 2 ) { confess 'invalid call'; }
    my ( $description, $contents ) = @_;

    if ( scalar(@PAGERCMD) ) {
        my $tmp      = File::Temp->new();
        my $filename = $tmp->filename;
        print $tmp $contents;
        close $tmp;

        $description = "$description ( press h for help or q to quit ) ";

        my @pager;
        foreach my $part (@PAGERCMD) {
            $part =~ s/\%PROMPT\%/$description/g;
            $part =~ s/\%FILENAME\%/$filename/g;
            push @pager, $part;
        }
        system @pager;
    } else {
        print $contents;
    }
}

sub generate_task_list {
    if ( scalar(@_) != 2 ) { confess 'invalid call' }
    my ( $num, $wchars ) = @_;

    my (@d) = get_task_filenames();
    my (@tasknums) = map { m/^(\d+)/; } @d;

    my $out = '';
    for my $tasknum ( sort { $a <=> $b } @tasknums ) {
        my $task = read_task($tasknum);

        my $title = $task->{header}->{title};
        my $desc  = $title;
        if ( defined($wchars) ) {
            $desc = substr( $title, 0, $wchars - length($tasknum) - 1 );
        }
        $out .= $PINFOCOLOR . $tasknum . ' ' . $PBOLDCOLOR . $desc . color('reset') . "\n";

        if ( defined($num) ) {

            # Exit the loop if we've displayed <num> entries
            $num--;
            if ( !$num ) { last; }
        }
    }

    return $out;
}

sub task_list {
    if ( scalar(@_) > 1 ) { confess 'invalid call' }
    my ($num) = @_;

    my $out = generate_task_list( $num, undef );

    display_with_pager( "Tasklist", $out );
}

sub task_monitor {
    if ( scalar(@_) != 0 ) { confess 'invalid call' }

    my $terminal = Term::Cap->Tgetent( { OSPEED => 9600 } );
    Term::ReadKey::ReadMode('raw');

    my $clear = $terminal->Tputs('cl');

    my $last = 'x';    # Not '' because then we won't try to draw the initial
                       # screen - there will be no "type any character" prompt!
    while (1) {
        my ( $wchar, $hchar, $wpixel, $hpixel ) = GetTerminalSize(*STDOUT);
        if ( !defined($wchar) ) { die "Terminal not supported"; }

        my $out = ( scalar localtime() ) . ' local / ' . ( scalar gmtime() ) . " UTC\n\n";
        $out .= generate_task_list( $hchar - 1, $wchar - 1 );
        if ( $out ne $last ) {
            $last = $out;
            print $clear;
            print $out;
            print color("reset") . "     ...Type any character to exit...  ";
        }
        if ( defined( Term::ReadKey::ReadKey(1) ) ) {
            Term::ReadKey::ReadMode('restore');
            say "";
            say "Exiting.";
            exit;
        }
    }
}

sub task_coalesce {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    coalesce_tasks();
    say "Coalesced tasks";
}

sub coalesce_tasks {
    if ( scalar(@_) != 0 ) { confess 'invalid call'; }

    my @d = get_task_filenames();
    my @nums = sort { $a <=> $b } map { s/-.*\.task$//; $_ } @d;

    my $i = 1;
    for my $num (@nums) {
        if ( $num > $i ) {
            my $orig = get_task_filename($num);
            my $new  = $orig;
            $new =~ s/^\d+//;
            $new = sprintf( "%05d%s", $i, $new );
            move $orig, $new;
            $i++;
        } elsif ( $i == $num ) {
            $i++;
        }
    }
}

1;

