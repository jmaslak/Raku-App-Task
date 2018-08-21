#!/usr/bin/env perl

#
# Copyright (C) 2015-2018 Joelle Maslak
# All Rights Reserved
#

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use autodie;
use App::Tasks;
use Carp;

MAIN: {
    my (@args) = @ARGV;
    @ARGV = ();
    App::Tasks::start(@args);
}

