#!/usr/bin/env perl

use Mojo::Base -strict;

use Data::Dump qw/pp/;
use DBI;

my $symbol_id = 1;
my $at        = '2017-09-21';

my $delta = 50 || $ARGV[0];
my $dte   = 30 || $ARGV[1];

$delta /= 100;

my $dbh = DBI->connect(
    'dbi:mysql:span:mysql',
    'admin',
    'admin',
    {RaiseError => 1},
);

# calculate expirations
my $sql = <<END;
SELECT DISTINCT expiration, DATEDIFF(expiration, at) AS dte
FROM options
WHERE symbol_id=?
  AND at=?
ORDER BY ABS(dte - ?)
LIMIT 2
END

my $expirations = $dbh->selectall_arrayref(
    $sql,
    {Slice => {}},
    $symbol_id,
    $at,
    $dte,
);

my $dte_total_diff = 0;
foreach my $expiration (@$expirations) {
    # DTE diff
    my $diff = abs($expiration->{dte} - $dte);
    $expiration->{diff} = $diff;
    $dte_total_diff += $diff;

    # calculate delta
    my $sql = <<END;
SELECT span_delta, implied_volatility
FROM options
WHERE symbol_id=?
  AND at=?
  AND expiration=?
  AND call_put=?
ORDER BY ABS(span_delta - ?)
LIMIT 2
END

    my $options = $dbh->selectall_arrayref(
        $sql,
        {Slice => {}},
        $symbol_id,
        $at,
        $expiration->{expiration},
        'P',
        $delta,
    );

    my $total_diff = 0;
    foreach my $option (@$options) {
        my $diff = abs($option->{span_delta} - $delta);
        $option->{diff} = $diff;
        $total_diff += $diff;
    }

    my $iv = 0;
    foreach my $option (@$options) {
        my $weigth = ($total_diff - $option->{diff}) / $total_diff;
        $iv += $weigth * $option->{implied_volatility};
    }

    $expiration->{implied_volatility} = $iv;
}

my $iv = 0;
foreach my $expiration (@$expirations) {
    my $weigth = ($dte_total_diff - $expiration->{diff}) / $dte_total_diff;
    $iv += $weigth * $expiration->{implied_volatility};
}

printf("%.2f\n", $iv * 100);

