package QRSmith::Encoder;
# Turns segments into the final interleaved codeword sequence: version and
# EC-level selection, terminator and padding, block split, Reed-Solomon
# check bytes and interleaving.
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);
use QRSmith::BitBuffer;
use QRSmith::Segment qw(total_bits segments_for_text);
use QRSmith::ReedSolomon qw(rs_encode);
use QRSmith::Tables qw(num_data_codewords num_raw_codewords ec_codewords_per_block num_ec_blocks);

our @EXPORT_OK = qw(plan_text plan_segments data_codewords split_blocks interleave);

my @LEVELS = qw(L M Q H);

# Choose version/level for a text. Returns a hashref with version, ecl,
# segments and data_bits. Dies if the text cannot fit.
sub plan_text {
    my ($text, %opt) = @_;
    my $strategy = $opt{strategy} // 'optimal';
    my ($minv, $maxv) = ($opt{min_version} // 1, $opt{max_version} // 40);
    for my $v ($minv .. $maxv) {
        # segment choice depends only on the version group, recompute at boundaries
        my $segs = segments_for_text($text, strategy => $strategy, version => $v);
        unshift @$segs, QRSmith::Segment::make_eci($opt{eci}) if defined $opt{eci};
        my $plan = eval { plan_segments($segs, %opt, min_version => $v, max_version => $v) };
        return $plan if $plan;
        die $@ if $@ && $@ !~ /does not fit/;
    }
    die "data does not fit in a version $minv-$maxv symbol at level " . ($opt{ecl} // 'M') . "\n";
}

sub plan_segments {
    my ($segs, %opt) = @_;
    my $ecl = $opt{ecl} // 'M';
    QRSmith::Tables::ecl_index($ecl);
    my ($minv, $maxv) = ($opt{min_version} // 1, $opt{max_version} // 40);
    croak 'invalid version range' if $minv < 1 || $maxv > 40 || $minv > $maxv;
    for my $v ($minv .. $maxv) {
        my $bits = total_bits($segs, $v);
        next unless defined $bits && $bits <= num_data_codewords($v, $ecl) * 8;
        if ($opt{boost} // 1) {     # use the strongest level that still fits for free
            for my $better (@LEVELS) {
                next if QRSmith::Tables::ecl_index($better) <= QRSmith::Tables::ecl_index($ecl);
                $ecl = $better if $bits <= num_data_codewords($v, $better) * 8;
            }
        }
        return { version => $v, ecl => $ecl, segments => $segs, data_bits => $bits };
    }
    die "data does not fit in a version $minv-$maxv symbol at level $ecl\n";
}

# Header, payload, terminator, bit padding and 0xEC/0x11 pad bytes.
sub data_codewords {
    my ($plan) = @_;
    my ($v, $ecl) = @$plan{qw(version ecl)};
    my $cap = num_data_codewords($v, $ecl) * 8;
    my $bb = QRSmith::BitBuffer->new;
    for my $s (@{ $plan->{segments} }) {
        $bb->append($s->mode_indicator, 4);
        $bb->append($s->num_chars, QRSmith::Segment::char_count_bits($s->mode, $v));
        $bb->append_buffer($s->data);
    }
    croak 'internal error: segments exceed capacity' if $bb->length > $cap;
    my $term = $cap - $bb->length;
    $bb->append(0, $term > 4 ? 4 : $term);
    $bb->append(0, (8 - $bb->length % 8) % 8);
    for (my $pad = 0xEC; $bb->length < $cap; $pad ^= 0xEC ^ 0x11) {
        $bb->append($pad, 8);
    }
    return $bb->to_bytes;
}

# Split data into blocks (short blocks first) and attach EC bytes.
# Returns arrayref of [ \@data, \@ecc ].
sub split_blocks {
    my ($data, $v, $ecl) = @_;
    my $nblocks = num_ec_blocks($v, $ecl);
    my $necc    = ec_codewords_per_block($v, $ecl);
    my $raw     = num_raw_codewords($v);
    croak 'data length does not match version/level' if @$data != num_data_codewords($v, $ecl);
    my $nshort   = $nblocks - $raw % $nblocks;
    my $shortlen = int($raw / $nblocks) - $necc;     # data bytes in a short block
    my @blocks;
    my $k = 0;
    for my $i (0 .. $nblocks - 1) {
        my $len = $shortlen + ($i < $nshort ? 0 : 1);
        my @d = @$data[ $k .. $k + $len - 1 ];
        $k += $len;
        push @blocks, [ \@d, rs_encode(\@d, $necc) ];
    }
    return \@blocks;
}

# Column-wise interleave: data bytes of every block, then EC bytes.
sub interleave {
    my ($blocks) = @_;
    my @out;
    my $maxd = 0;
    for (@$blocks) { $maxd = @{ $_->[0] } if @{ $_->[0] } > $maxd }
    for my $i (0 .. $maxd - 1) {
        push @out, map { $i < @{ $_->[0] } ? $_->[0][$i] : () } @$blocks;
    }
    my $necc = @{ $blocks->[0][1] };
    for my $i (0 .. $necc - 1) { push @out, map { $_->[1][$i] } @$blocks }
    return \@out;
}

1;
