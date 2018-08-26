#!/usr/bin/env perl6
use v6;

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

use App::Tasks;

sub MAIN(+@args) {
    App::Tasks::start(@args);
}

