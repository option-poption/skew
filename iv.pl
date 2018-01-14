#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use IV;


my $iv = IV->new(
    at    => '2017-09-21',
    dte   => 30,
    delta => 0.5,
);

printf("%.2f\n", $iv->iv * 100);

