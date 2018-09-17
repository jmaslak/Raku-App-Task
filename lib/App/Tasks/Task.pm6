use v6;

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

use v6;

class App::Tasks::Task:ver<0.0.1>:auth<cpan:JMASLAK> {
    use App::Tasks::TaskBody;

    has Int                  $.task-number;
    has IO::Path             $.data-dir;
    has Str                  $.title;
    has DateTime             $.created;
    has Date                 $.expires;
    has App::Tasks::TaskBody @.body;

    # Read a file to build a new task object
    method from-file(IO::Path:D $data-dir, Int:D $task-number -->App::Tasks::Task:D) {
        my $file = get-task-file($data-dir, $task-number);
        my @lines = $file.lines;

        my Str      $title;
        my DateTime $created;
        my Date     $expires;

        # Headers
        while (@lines) {
            # Do we see the start of a new body?
            if @lines[0] ~~ m/^ '--- ' \d+ $/ { last; }
            
            my $line = @lines.shift;
            if $line !~~ m/^ ( \w+ ) ':' \s* ( .* ) $/ {
                die("Invalid header line in " ~ $file.Str ~ ": $line");
            }

            $line ~~ m/^ ( \w+ ) ':' \s* ( .* ) $/;
            my $field = $0.Str.fc;
            my $value = $1.Str;

            given $field {
                when 'title'   { $title   = $value }
                when 'created' { $created = DateTime.new( $value.Int ) }
                when 'expires' { $expires = Date.new($value) }
                default        { die("Unknown header: $field") }
            }
        }

        if ! $title.defined   { die("Title field not found") }
        if ! $created.defined { die("Created field not found") }

        # Notes
        my @body;
        while (@lines) {
            @lines.shift ~~ m/^ '--- ' ( \d+ ) $/;
            my $date = DateTime.new( $0.Str.Int );

            # We read an individual body part
            my @bodyline;
            while (@lines) {
                if @lines[0] ~~ m/^ '--- ' \d+ $/ { last; }
                push @bodyline = @lines.shift;
            }

            @body.push: App::Tasks::TaskBody.new(
                :date($date),
                :text(@bodyline.join("\n")),
            );
        }

        # Create the object
        return self.new(
            :task-number($task-number),
            :data-dir($data-dir),
            :title($title),
            :created($created),
            :expires($expires),
            :body(@body),
        );
    }

    # Write to a file
    method to-file(-->Nil) {
        # Basic requirements for a task
        if ! self.data-dir.defined    { die("Data directory not defined") }
        if ! self.task-number.defined { die("Task number not defined") }

        # Header requirements
        if ! self.title.defined    { die("Title field not found") }
        if ! self.created.defined  { die("Created field not found") }

        my $file = self.data-dir.add( self.task-number.fmt("%05d") ~ "-none.task" );
        my $fh = $file.open(:w);

        # Header, mandatory
        $fh.say: "Title: ",   self.title;
        $fh.say: "Created: ", self.created.posix;

        # Header, optional
        $fh.say: "Expires: ", self.expires if self.expires.defined;

        # Body
        for self.body -> $body {
            $fh.say: "--- ", $body.date.posix;
            $fh.say: $body.text;
        }

        $fh.close;
    }

    # Get the filename associated with a task number
    my sub get-task-file(IO::Path:D $data-dir, Int:D $task-number -->IO::Path) {
        my $partial-fn = $task-number.fmt("%05d");
        my @match = $data-dir.dir: test => /^ $partial-fn '-' .+ '.task' $ /;

        given @match.elems {
            when 1  { return @match[0] }
            when 0  { return }
            default { die("More than one name matches\n") }
        }
    }
}

