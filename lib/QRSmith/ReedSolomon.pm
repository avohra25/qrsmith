package QRSmith::ReedSolomon;
# Reed-Solomon codes over GF(256) as used by QR Code: the generator
# polynomial has roots alpha^0 .. alpha^(n-1). Encoding is systematic
# (data followed by n check bytes). Decoding corrects up to floor(n/2)
# byte errors, or more when erasure positions are known (2e + f <= n),
# using syndromes, Berlekamp-Massey, a Chien search and Forney's formula.
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);
use QRSmith::GF256 qw(gf_mul gf_div gf_exp gf_pow gf_inv poly_eval poly_mul poly_add poly_scale);

our @EXPORT_OK = qw(rs_generator rs_encode rs_syndromes rs_decode);

my %GEN_CACHE;

sub rs_generator {
    my ($n) = @_;
    croak "check symbol count must be 1..254, got $n" if $n < 1 || $n > 254;
    return $GEN_CACHE{$n} //= do {
        my $g = [1];
        $g = poly_mul($g, [ 1, gf_exp($_) ]) for 0 .. $n - 1;
        $g;
    };
}

# Returns the n check bytes for @$data (remainder of data*x^n / g).
sub rs_encode {
    my ($data, $n) = @_;
    croak 'codeword too long for GF(256)' if @$data + $n > 255;
    my $g = rs_generator($n);
    my @rem = (0) x $n;
    for my $byte (@$data) {
        my $factor = $byte ^ shift @rem;
        push @rem, 0;
        if ($factor) {
            $rem[ $_ - 1 ] ^= gf_mul($g->[$_], $factor) for 1 .. $n;
        }
    }
    return \@rem;
}

# S_i = C(alpha^i) for i = 0 .. n-1. All zero means no detectable error.
sub rs_syndromes {
    my ($msg, $n) = @_;
    return [ map { poly_eval($msg, gf_exp($_)) } 0 .. $n - 1 ];
}

# Decode a full codeword (data + n check bytes). Optional erasures is a
# list of byte indices known to be bad. Returns
#   (\@corrected_codeword, $number_of_corrected_bytes)
# and dies with "uncorrectable" when the errors exceed the code's capacity.
sub rs_decode {
    my ($msg_in, $n, $erasures) = @_;
    $erasures //= [];
    my @msg = @$msg_in;
    my $len = @msg;
    croak 'codeword shorter than check symbol count' if $len < $n;
    croak 'too many erasures' if @$erasures > $n;

    my $synd = rs_syndromes(\@msg, $n);
    return (\@msg, 0) unless grep { $_ } @$synd;

    # Erasure locator Gamma(x) = prod (1 - X_j x), with X_j = alpha^(len-1-pos).
    # Polynomials in this routine are stored lowest degree first.
    my @gamma = (1);
    for my $pos (@$erasures) {
        croak "erasure position $pos out of range" if $pos < 0 || $pos >= $len;
        my $X = gf_exp($len - 1 - $pos);
        my @next = (@gamma, 0);
        $next[ $_ + 1 ] ^= gf_mul($gamma[$_], $X) for 0 .. $#gamma;
        @gamma = @next;
    }

    # Berlekamp-Massey on the modified syndromes, seeded with Gamma.
    my @lambda = @gamma;
    my @prev   = @gamma;
    my $L = scalar @$erasures;
    my $m = 1;
    my $b = 1;
    for my $r ($L .. $n - 1) {
        my $delta = 0;
        for my $i (0 .. $#lambda) {
            $delta ^= gf_mul($lambda[$i], $synd->[ $r - $i ]) if $r - $i >= 0;
        }
        if ($delta == 0) {
            $m++;
            next;
        }
        my $coef = gf_div($delta, $b);
        my @t = @lambda;
        my $need = @prev + $m;
        push @lambda, (0) x ($need - @lambda) if @lambda < $need;
        $lambda[ $_ + $m ] ^= gf_mul($coef, $prev[$_]) for 0 .. $#prev;
        if (2 * $L <= $r + scalar(@$erasures)) {
            $L = $r + 1 + scalar(@$erasures) - $L;
            @prev = @t;
            $b = $delta;
            $m = 1;
        }
        else {
            $m++;
        }
    }
    pop @lambda while @lambda > 1 && $lambda[-1] == 0;
    my $deg = $#lambda;
    die "uncorrectable: too many errors\n" if 2 * ($deg - @$erasures) + @$erasures > $n;

    # Chien search: positions p where Lambda(X_p^-1) == 0.
    my @pos;
    for my $p (0 .. $len - 1) {
        my $xinv = gf_exp(255 - (($len - 1 - $p) % 255));
        my $v = 0;
        my $xp = 1;
        for my $c (@lambda) {
            $v ^= gf_mul($c, $xp);
            $xp = gf_mul($xp, $xinv);
        }
        push @pos, $p if $v == 0;
    }
    die "uncorrectable: error locator has wrong number of roots\n" if @pos != $deg;

    # Omega(x) = S(x) * Lambda(x) mod x^n
    my @omega = (0) x $n;
    for my $i (0 .. $n - 1) {
        for my $j (0 .. $#lambda) {
            last if $i + $j >= $n;
            $omega[ $i + $j ] ^= gf_mul($synd->[$i], $lambda[$j]);
        }
    }

    # Forney (first consecutive root b = 0): e = X * Omega(X^-1) / Lambda'(X^-1)
    for my $p (@pos) {
        my $X    = gf_exp($len - 1 - $p);
        my $xinv = gf_inv($X);
        my $om = 0;
        my $xp = 1;
        for my $c (@omega) { $om ^= gf_mul($c, $xp); $xp = gf_mul($xp, $xinv); }
        my $dl = 0;
        for (my $k = 1; $k <= $#lambda; $k += 2) {      # odd terms survive in char 2
            $dl ^= gf_mul($lambda[$k], gf_pow($xinv, $k - 1));
        }
        die "uncorrectable: zero derivative\n" if $dl == 0;
        $msg[$p] ^= gf_mul($X, gf_div($om, $dl));
    }

    die "uncorrectable: residual syndrome after correction\n"
        if grep { $_ } @{ rs_syndromes(\@msg, $n) };
    return (\@msg, scalar @pos);
}

1;
