use v6.c;

#
# Copyright © 2018 Joelle Maslak
# All Rights Reserved - See License
#

class App::Tasks::TaskBody:ver<0.4.0>:auth<zef:jmaslak> {
    has DateTime $.date;
    has Str      $.text;
}

