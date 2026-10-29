package QRSmith::Tables;
# Capacity tables from ISO/IEC 18004:2015 (Table 9) and helpers derived
# from the symbol geometry.
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);

our @EXPORT_OK = qw(ec_codewords_per_block num_ec_blocks raw_data_modules
                    num_data_codewords num_raw_codewords alignment_positions
                    ecl_index ecl_format_bits symbol_size);

# Indexed [ecl][version]; ecl order L, M, Q, H. Index 0 is unused.
my @ECC_PER_BLOCK = (
    [ -1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 ],
    [ -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 ],
    [ -1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 ],
    [ -1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 ],
);
my @NUM_BLOCKS = (
    [ -1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25 ],
    [ -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 ],
    [ -1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68 ],
    [ -1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81 ],
);

my %ECL_INDEX  = (L => 0, M => 1, Q => 2, H => 3);
my %ECL_FORMAT = (L => 1, M => 0, Q => 3, H => 2);    # 2-bit field in format info

sub ecl_index {
    my ($ecl) = @_;
    croak "unknown error correction level '$ecl' (use L, M, Q or H)"
        unless defined $ecl && exists $ECL_INDEX{$ecl};
    return $ECL_INDEX{$ecl};
}
sub ecl_format_bits { ecl_index($_[0]); $ECL_FORMAT{ $_[0] } }

sub _check_version {
    my ($v) = @_;
    croak "version must be an integer 1..40, got '$v'"
        unless defined $v && $v =~ /^\d+$/ && $v >= 1 && $v <= 40;
}

sub symbol_size { _check_version($_[0]); 4 * $_[0] + 17 }

sub ec_codewords_per_block { _check_version($_[0]); $ECC_PER_BLOCK[ ecl_index($_[1]) ][ $_[0] ] }
sub num_ec_blocks          { _check_version($_[0]); $NUM_BLOCKS[ ecl_index($_[1]) ][ $_[0] ] }

# Modules available for data+EC after removing every function pattern.
sub raw_data_modules {
    my ($v) = @_;
    _check_version($v);
    my $r = (16 * $v + 128) * $v + 64;
    if ($v >= 2) {
        my $na = int($v / 7) + 2;
        $r -= (25 * $na - 10) * $na - 55;
        $r -= 36 if $v >= 7;
    }
    return $r;
}

sub num_raw_codewords { int(raw_data_modules($_[0]) / 8) }

sub num_data_codewords {
    my ($v, $ecl) = @_;
    return num_raw_codewords($v) - ec_codewords_per_block($v, $ecl) * num_ec_blocks($v, $ecl);
}

# Centre coordinates of alignment patterns along one axis.
sub alignment_positions {
    my ($v) = @_;
    _check_version($v);
    return () if $v == 1;
    my $na   = int($v / 7) + 2;
    my $size = symbol_size($v);
    my $step = $v == 32 ? 26 : 2 * int(($v * 8 + $na * 3 + 5) / ($na * 4 - 4));
    my @pos = (6);
    for (my $p = $size - 7; @pos < $na; $p -= $step) {
        splice @pos, 1, 0, $p;
    }
    return @pos;
}

1;
