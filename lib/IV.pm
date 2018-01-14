package IV;

use strict;
use warnings;

use Carp qw/carp croak/;
use DBI;


sub new {
    my ($class, %arg) = @_;
    
    my $self = bless({}, $class);

    $self->{dbh} = $arg{dbh} || DBI->connect(
        'dbi:mysql:span:mysql',
        'admin',
        'admin',
        {RaiseError => 1},
    );

    # default params
    $self->{at}         = $arg{at};
    $self->{call_put}   = $arg{call_put} || 'P';
    $self->{delta}      = $arg{delta};
    $self->{dte}        = $arg{dte};
    $self->{expiration} = $arg{expiration};
    $self->{symbol_id}  = $arg{symbol_id} || 1;

    return $self;
}

sub iv {
    my ($self, %arg) = @_;

    my $at         = $arg{at}         || $self->{at}       or croak 'AT missing';
    my $call_put   = $arg{call_put}   || $self->{call_put} or croak 'CALL_PUT missing';
    my $delta      = $arg{delta}      || $self->{delta}    or croak 'DELTA missing';
    my $dte        = $arg{dte}        || $self->{dte};
    my $expiration = $arg{expiration} || $self->{expiration};

    croak 'DTE or EXPIRATION missing' unless $dte || $expiration;
    carp 'EXPIRATION overwrites DTE' if $dte && $expiration;

    if ($expiration) {
        return $self->_iv_for_expiration(
            at         => $at,
            call_put   => $call_put,
            delta      => $delta,
            expiration => $expiration,
        );
    }

    return $self->_iv_for_dte(
        at       => $at,
        call_put => $call_put,
        delta    => $delta,
        dte      => $dte,
    );
}

sub _iv_for_expiration {
    my ($self, %arg) = @_;

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

    my $options = $self->{dbh}->selectall_arrayref(
        $sql,
        {Slice => {}},
        $self->{symbol_id},
        $arg{at},
        $arg{expiration},
        $arg{call_put},
        $arg{delta},
    );

    my $total = 0;
    foreach my $option (@$options) {
        my $diff = abs($option->{span_delta} - $arg{delta});
        $option->{diff} = $diff;
        $total += $diff;
    }

    my $iv = 0;
    foreach my $option (@$options) {
        my $weigth = ($total - $option->{diff}) / $total;
        $iv += $weigth * $option->{implied_volatility};
    }

    return $iv;
}

sub _iv_for_dte {
    my ($self, %arg) = @_;

    my $sql = <<END;
SELECT DISTINCT expiration, DATEDIFF(expiration, at) AS dte
FROM options
WHERE symbol_id=?
  AND at=?
ORDER BY ABS(dte - ?)
LIMIT 2
END

    my $expirations = $self->{dbh}->selectall_arrayref(
        $sql,
        {Slice => {}},
        $self->{symbol_id},
        $arg{at},
        $arg{dte},
    );

    my $total = 0;
    foreach my $expiration (@$expirations) {
        # DTE diff
        my $diff = abs($expiration->{dte} - $arg{dte});
        $expiration->{diff} = $diff;
        $total += $diff;

        $expiration->{iv} = $self->_iv_for_expiration(
            at         => $arg{at},
            call_put   => $arg{call_put},
            delta      => $arg{delta},
            expiration => $expiration->{expiration},
        );
    }

    my $iv = 0;
    foreach my $expiration (@$expirations) {
        my $weigth = ($total - $expiration->{diff}) / $total;
        $iv += $weigth * $expiration->{iv};
    }

    return $iv;
}

1;

