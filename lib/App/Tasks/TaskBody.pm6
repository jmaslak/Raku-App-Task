use v6;

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

use v6;

class App::Tasks::TaskBody:ver<0.0.4>:auth<cpan:JMASLAK> {
    has DateTime $.date;
    has Str      $.text;
}

