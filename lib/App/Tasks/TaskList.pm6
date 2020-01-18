use v6.c;

#
# Copyright © 2018 Joelle Maslak
# All Rights Reserved - See License
#

unit class App::Tasks::TaskList:ver<0.0.17>:auth<cpan:JMASLAK>;

use App::Tasks::Lock;
use App::Tasks::Task;

has IO::Path:D         $.data-dir is required;
has IO::Path:D         $.lock-file = $!data-dir.add(".taskview.lock");
has App::Tasks::Lock:D $.lock      = App::Tasks::Lock.new( :lock-file($!lock-file) );

# Force a read of the tasks
method read-tasks(--> Array[App::Tasks::Task:D]) {
    $!lock.get-lock;
    LEAVE $!lock.release-lock;

    my @d        = self.get-task-filenames;
    my @tasknums = @d.map: { $^a.basename ~~ m/^ (\d+) /; Int($0); };
    @tasknums = @tasknums.sort( { $^a <=> $^b } ).list;

    my App::Tasks::Task:D @tasks;
    @tasks = @tasknums.hyper(batch => 8, degree => 16).map: {
        App::Tasks::Task.from-file($!data-dir, $^tasknum);
    }

    return @tasks;
}

# Get task filename list
method get-task-filenames(-->Array[IO::Path:D]) {
    $!lock.get-lock;
    LEAVE $!lock.release-lock;

    my IO::Path:D @tasks = $!data-dir.dir(test => { m/^ \d+ '-' .* \.task $ / }).sort;
    return @tasks;
}

# Is the task valid?
method exists(Int:D $tasknum -->Bool:D) {
    my @tasks = self.read-tasks();
    if @tasks.first( { $^a.task-number == $tasknum } ).defined {
        return True;
    } else {
        return False;
    }
}

