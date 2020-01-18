use v6.c;

#
# Copyright © 2018 Joelle Maslak
# All Rights Reserved - See License
#

class App::Tasks::Lock:ver<0.0.17>:auth<cpan:JMASLAK> {
    my Lock:D     $SEMAPHORE = Lock.new;
    my Int:D      $LOCKCNT   = 0;
    my IO::Handle $LOCK;

    has IO::Path:D $.lock-file is required;

    method get-lock(-->Bool:D)      { $SEMAPHORE.protect: { increment-lock($.lock-file) } }
    method release-lock(-->Bool:D)  { $SEMAPHORE.protect: { decrement-lock } }
    method get-lock-count(-->Int:D) { $LOCKCNT }

    # Not threadsafe, must be wrapped in a $SEMAPHORE.protect
    my sub increment-lock(IO::Path:D $lock-file -->Bool:D) {
        $LOCKCNT++;
        if $LOCKCNT == 1 {
            $LOCK = $lock-file.open(:a);
            $LOCK.lock;
            return True;
        } elsif $LOCKCNT ≥ 80 {
            die("Lock leak detected");
        }

        return False;
    }

    # Not threadsafe, must be wrapped in a $SEMAPHORE.protect
    my sub decrement-lock(-->Bool:D) {
        $LOCKCNT--;
        if $LOCKCNT == 0 {
            $LOCK.unlock;
            $LOCK.close;
            return True;
        } elsif $LOCKCNT < 0 {
            die("Lock released when no lock present");
        }

        return False;
    }
};



