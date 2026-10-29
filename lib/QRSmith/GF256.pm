package QRSmith::GF256;
# Arithmetic in GF(2^8) with the QR Code field polynomial
# x^8 + x^4 + x^3 + x^2 + 1 (0x11D) and generator alpha = 2.
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);

our @EXPORT_OK = qw(gf_add gf_mul gf_div gf_inv gf_pow gf_exp gf_log
                    poly_eval poly_mul poly_scale poly_add);

my (@EXP, @LOG);
{
    my $x = 1;
    for my $i (0 .. 254) {
        $EXP[$i] = $x;
        $LOG[$x] = $i;
        $x <<= 1;
        $x ^= 0x11D if $x & 0x100;
    }
    $EXP[$_] = $EXP[$_ - 255] for 255 .. 511;   # avoids a modulo in gf_mul
}

sub gf_add { $_[0] ^ $_[1] }

sub gf_exp { $EXP[ $_[0] % 255 ] }

sub gf_log {
    my ($x) = @_;
    croak 'log(0) is undefined in GF(256)' if $x == 0;
    return $LOG[$x];
}

sub gf_mul {
    my ($x, $y) = @_;
    return 0 if $x == 0 || $y == 0;
    return $EXP[ $LOG[$x] + $LOG[$y] ];
}

sub gf_div {
    my ($x, $y) = @_;
    croak 'division by zero in GF(256)' if $y == 0;
    return 0 if $x == 0;
    return $EXP[ ($LOG[$x] - $LOG[$y] + 255) % 255 ];
}

sub gf_inv { gf_div(1, $_[0]) }

sub gf_pow {
    my ($x, $n) = @_;
    return 1 if $n == 0;
    return 0 if $x == 0;
    return $EXP[ (($LOG[$x] * $n) % 255 + 255) % 255 ];
}

# Polynomials are array refs of coefficients, highest degree first.

sub poly_eval {
    my ($p, $x) = @_;
    my $y = 0;
    $y = gf_mul($y, $x) ^ $_ for @$p;   # Horner's rule
    return $y;
}

sub poly_scale {
    my ($p, $s) = @_;
    return [ map { gf_mul($_, $s) } @$p ];
}

sub poly_add {
    my ($p, $q) = @_;
    my $n = @$p > @$q ? scalar @$p : scalar @$q;
    my @r = (0) x $n;
    $r[ $_ + $n - @$p ] = $p->[$_] for 0 .. $#$p;
    $r[ $_ + $n - @$q ] ^= $q->[$_] for 0 .. $#$q;
    return \@r;
}

sub poly_mul {
    my ($p, $q) = @_;
    my @r = (0) x (@$p + @$q - 1);
    for my $i (0 .. $#$p) {
        next unless $p->[$i];
        for my $j (0 .. $#$q) {
            $r[ $i + $j ] ^= gf_mul($p->[$i], $q->[$j]);
        }
    }
    return \@r;
}

1;
