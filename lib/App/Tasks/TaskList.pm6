use v6;

#
# Copyright © 2018 Joelle Maslak
# All Rights Reserved - See License
#

unit class App::Tasks::TaskList:ver<0.0.9>:auth<cpan:JMASLAK>;

use App::Tasks::Lock;
use App::Tasks::Task;

has IO::Path:D         $.data-dir is required;
has IO::Path:D         $.lock-file = $!data-dir.add(".taskview.lock");
has App::Tasks::Lock:D $.lock      = App::Tasks::Lock.new( :lock-file($!lock-file) );

