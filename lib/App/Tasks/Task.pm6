use v6;

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

use v6;

class App::Tasks::Task:ver<0.0.7>:auth<cpan:JMASLAK> {
    use App::Tasks::TaskBody;

    has Int:D      $.task-number is required;
    has IO::Path:D $.data-dir    is required;
    has IO::Path   $.file;
    has Str:D      $.title       is required;
    has DateTime:D $.created     is required;
    has Date       $.expires;
    has Date       $.not-before;  # Hide before this date
    has Array:D    $.body = Array[App::Tasks::TaskBody].new;
    has Int:D      $.task-id = new-task-id;
    has Int:D      $.version = 2;
    has Int        $.display-frequency;

    # Read a file to build a new task object
    method from-file(IO::Path:D $data-dir, Int:D $task-number -->App::Tasks::Task:D) {
        my $file  = get-task-file($data-dir, $task-number);
        if ! $file.defined { die("Task $task-number does not exist\n"); }
        my @lines = $file.lines;

        my Str      $title;
        my DateTime $created;
        my Date     $expires;
        my Date     $not-before;
        my Int      $task-id;
        my Int      $display-frequency;

        # Headers
        while (@lines) {
            # Do we see the start of a new body?
            if @lines[0] ~~ m/^ '--- ' \d+ $/ { last; }
            
            my $line = @lines.shift;
            if $line !~~ m/^ ( [ \- | \w ]+ ) ':' \s* ( .* ) $/ {
                die("Invalid header line in " ~ $file.Str ~ ": $line");
            }

            $line ~~ m/^ ( [ \- | \w ]+ ) ':' \s* ( .* ) $/;
            my $field = $0.Str.fc;
            my $value = $1.Str;

            given $field {
                when 'title'             { $title             = $value }
                when 'created'           { $created           = DateTime.new($value.Int) }
                when 'expires'           { $expires           = Date.new($value) }
                when 'not-before'        { $not-before        = Date.new($value) }
                when 'task-id'           { $task-id           = $value.Int }
                when 'display-frequency' { $display-frequency = $value.Int }
                default           { die("Unknown header: $field") }
            }
        }

        # Required fields
        if ! $title.defined   { die("Title field not found") }
        if ! $created.defined { die("Created field not found") }

        my $version = 2;

        # Defaults
        if ! $task-id {
            $task-id = new-task-id;
            $version = 1; # We are dealing with a VERSION 1 file.
        }

        # Notes
        my @body;
        while (@lines) {
            @lines.shift ~~ m/^ '--- ' ( \d+ ) $/;
            my $date = DateTime.new( $0.Str.Int );

            # We read an individual body part
            my @bodyline;
            while (@lines) {
                if @lines[0] ~~ m/^ '--- ' \d+ $/ { last; }
                @bodyline.push: @lines.shift;
            }

            @body.push: App::Tasks::TaskBody.new(
                :date($date),
                :text(@bodyline.join("\n")),
            );
        }

        my $obj = self.new(
            :task-number($task-number),
            :data-dir($data-dir),
            :file($file),
            :title($title),
            :created($created),
            :expires($expires),
            :not-before($not-before),
            :display-frequency($display-frequency),
            :task-id($task-id),
            :body(@body),
        );

        if $version < 2 {
            $obj.to-file;  # This will update the version on disk.
        }

        return $obj;
    }

    # Write to a file
    method to-file(-->Nil) {
        # Basic requirements for a task
        if ! self.data-dir.defined    { die("Data directory not defined") }
        if ! self.task-number.defined { die("Task number not defined") }

        # Header requirements
        if ! self.title.defined    { die("Title field not found") }
        if ! self.created.defined  { die("Created field not found") }

        if ! $.file.defined {
            $!file = self.data-dir.add( self.task-number.fmt("%05d") ~ "-none.task" );
        }
        my $fh = $.file.open(:w);

        # Header, mandatory
        $fh.say: "Title: ",   self.title;
        $fh.say: "Created: ", self.created.posix;
        $fh.say: "Task-Id: ", self.task-id;

        # Headers, optional
        $fh.say: "Expires: ",           self.expires           if self.expires.defined;
        $fh.say: "Not-Before: ",        self.not-before        if self.not-before.defined;
        $fh.say: "Display-Frequency: ", self.display-frequency if self.display-frequency.defined;

        # Body
        for self.body -> $body {
            $fh.say: "--- ", $body.date.posix;
            $fh.say: $body.text;
        }

        $fh.close;
    }

    # Add a task note to this object
    method add-note(Str:D $text) {
        my $note-text = S/\n $// given $text;

        my $note = App::Tasks::TaskBody.new(:date(DateTime.now), :text($note-text));
        $!body.push: $note;
    }

    # Update title
    method change-title(Str:D $text) {
        $!title = $text;
    }

    # Update Expiration
    method change-expiration(Date $day) {
        $!expires = $day;
    }

    # Update Not-Before
    method change-not-before(Date $day) {
        $!not-before = $day;
    }

    # Update Display-Frequency
    method change-display-frequency(Int:D $frequency where * ≥ 0) {
        $!display-frequency = $frequency;
    }

    # Is task mature?
    method is-mature(-->Bool:D) {
        if ! self.not-before.defined { return True }

        if self.not-before ≤ Date.new(DateTime.now.local.Date.Str) {
            return True;
        } else {
            return False;
        }
    }

    # Check Frequency
    method frequency-display-today(-->Bool:D) {
        if ! self.display-frequency.defined { return True }
        if self.display-frequency ≤ 1       { return True }

        my $daynum = Date.new(DateTime.now.local.Date.Str).daycount;
        if ( self.task-id + $daynum ) %% self.display-frequency {
            return True;
        } else {
            return False;
        }
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

    # Method to create a message-id
    # This will be unique-enough for our purposes, but we should 
    our sub new-task-id(-->Int:D) {
        my $date = DateTime.now;
        my $posix = $date.posix;
        my $fracs = $date.second - $date.whole-second;
        my $roll  = (^4_000_000_000).roll;

        my Int $task-id = Int(($posix + $fracs) * 1_000) * 4_000_000_000 + $roll;

        return $task-id;
    }
}

