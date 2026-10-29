package QRSmith::Segment;
# Data segments (numeric, alphanumeric, byte, ECI) and mode selection,
# including an optimal mode-switching planner.
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);
use QRSmith::BitBuffer;

our @EXPORT_OK = qw(make_numeric make_alphanumeric make_bytes make_eci
                    segments_for_text total_bits is_numeric is_alphanumeric
                    char_count_bits);

my $ALNUM = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
my %ALNUM_VAL;
@ALNUM_VAL{ split //, $ALNUM } = 0 .. length($ALNUM) - 1;

# mode => [indicator, char-count bits for versions 1-9, 10-26, 27-40]
my %MODE = (
    numeric      => [ 0x1, 10, 12, 14 ],
    alphanumeric => [ 0x2, 9,  11, 13 ],
    byte         => [ 0x4, 8,  16, 16 ],
    eci          => [ 0x7, 0,  0,  0 ],
);

sub _group { my $v = shift; $v <= 9 ? 1 : $v <= 26 ? 2 : 3 }

sub char_count_bits {
    my ($mode, $version) = @_;
    croak "unknown mode '$mode'" unless $MODE{$mode};
    return $MODE{$mode}[ _group($version) ];
}

sub mode_indicator { $MODE{ $_[0]{mode} }[0] }
sub mode      { $_[0]{mode} }
sub num_chars { $_[0]{num_chars} }
sub data      { $_[0]{data} }       # BitBuffer

sub is_numeric      { $_[0] =~ /\A[0-9]*\z/ }
sub is_alphanumeric { $_[0] =~ /\A[0-9A-Z \$%*+\-.\/:]*\z/ }

sub _new {
    my ($mode, $n, $bb) = @_;
    return bless { mode => $mode, num_chars => $n, data => $bb }, __PACKAGE__;
}

sub make_numeric {
    my ($digits) = @_;
    croak 'numeric segment accepts only 0-9' unless is_numeric($digits);
    my $bb = QRSmith::BitBuffer->new;
    for (my $i = 0; $i < length $digits; $i += 3) {
        my $chunk = substr $digits, $i, 3;
        $bb->append($chunk + 0, 3 * length($chunk) + 1);   # 3 digits -> 10 bits, 2 -> 7, 1 -> 4
    }
    return _new(numeric => length $digits, $bb);
}

sub make_alphanumeric {
    my ($text) = @_;
    croak 'alphanumeric segment accepts only 0-9 A-Z space $%*+-./:' unless is_alphanumeric($text);
    my $bb = QRSmith::BitBuffer->new;
    my @c = split //, $text;
    while (@c >= 2) {
        my ($a, $b) = splice @c, 0, 2;
        $bb->append($ALNUM_VAL{$a} * 45 + $ALNUM_VAL{$b}, 11);
    }
    $bb->append($ALNUM_VAL{ $c[0] }, 6) if @c;
    return _new(alphanumeric => length $text, $bb);
}

# Takes a byte string (characters 0-255). Encode text to UTF-8 first.
sub make_bytes {
    my ($bytes) = @_;
    croak 'byte segment needs a byte string; encode wide characters to UTF-8 first'
        if $bytes =~ /[^\x00-\xFF]/;
    my $bb = QRSmith::BitBuffer->new;
    $bb->append(ord, 8) for split //, $bytes;
    return _new(byte => length $bytes, $bb);
}

# Extended Channel Interpretation designator, e.g. 26 for UTF-8.
sub make_eci {
    my ($assign) = @_;
    my $bb = QRSmith::BitBuffer->new;
    if    ($assign < 0)       { croak 'ECI assignment must be non-negative' }
    elsif ($assign < 1 << 7)  { $bb->append($assign, 8) }
    elsif ($assign < 1 << 14) { $bb->append(0b10, 2)->append($assign, 14) }
    elsif ($assign < 1e6)     { $bb->append(0b110, 3)->append($assign, 21) }
    else                      { croak 'ECI assignment must be below 1000000' }
    return _new(eci => 0, $bb);
}

# Bits needed for these segments at a version, or undef if a count overflows.
sub total_bits {
    my ($segs, $version) = @_;
    my $total = 0;
    for my $s (@$segs) {
        my $cc = char_count_bits($s->{mode}, $version);
        return undef if $s->{num_chars} >= 2**$cc && $s->{mode} ne 'eci';
        $total += 4 + $cc + $s->{data}->length;
    }
    return $total;
}

sub _utf8_bytes {
    my ($s) = @_;
    my $b = $s;
    utf8::encode($b) if utf8::is_utf8($b) || $b =~ /[^\x00-\xFF]/;
    return $b;
}

# Build segments for a character string.
#   strategy 'auto'    - one segment in the most compact single mode
#   strategy 'optimal' - minimal-length mix of modes for the given version
#   strategy 'byte'    - always UTF-8 bytes
sub segments_for_text {
    my ($text, %opt) = @_;
    my $strategy = $opt{strategy} // 'optimal';
    my $version  = $opt{version} // 1;
    return [] if $text eq '';
    if ($strategy eq 'byte') { return [ make_bytes(_utf8_bytes($text)) ] }
    if ($strategy eq 'auto') {
        return [ make_numeric($text) ]      if is_numeric($text);
        return [ make_alphanumeric($text) ] if is_alphanumeric($text);
        return [ make_bytes(_utf8_bytes($text)) ];
    }
    croak "unknown segmentation strategy '$strategy'" unless $strategy eq 'optimal';
    return _optimal($text, $version);
}

# Dynamic programming over characters. Costs are in sixths of a bit so that
# numeric (10/3 bits per char) and alphanumeric (11/2) are exact integers.
sub _optimal {
    my ($text, $version) = @_;
    my @chars = split //, $text;
    my @modes = qw(byte alphanumeric numeric);
    my %head  = map { $_ => (4 + char_count_bits($_, $version)) * 6 } @modes;
    my $ceil6 = sub { my $x = shift; int(($x + 5) / 6) * 6 };
    my (@cost, @back);
    for my $i (0 .. $#chars) {
        my $c = $chars[$i];
        my %ccost = (byte => 48 * length(_utf8_bytes($c)));
        $ccost{alphanumeric} = 33 if exists $ALNUM_VAL{$c};
        $ccost{numeric}      = 20 if $c =~ /\A[0-9]\z/;
        for my $m (@modes) {
            next unless defined $ccost{$m};
            my ($best, $from);
            if ($i == 0) {
                ($best, $from) = ($head{$m}, undef);
            }
            else {
                for my $k (@modes) {
                    next unless defined $cost[ $i - 1 ]{$k};
                    my $cand = $k eq $m ? $cost[ $i - 1 ]{$k}
                                        : $ceil6->($cost[ $i - 1 ]{$k}) + $head{$m};
                    ($best, $from) = ($cand, $k) if !defined $best || $cand < $best;
                }
            }
            $cost[$i]{$m} = $best + $ccost{$m};
            $back[$i]{$m} = $from;
        }
    }
    my ($mode) = sort { $ceil6->($cost[-1]{$a}) <=> $ceil6->($cost[-1]{$b}) }
                 grep { defined $cost[-1]{$_} } @modes;
    my @plan;
    for (my $i = $#chars; $i >= 0; $i--) {
        unshift @plan, $mode;
        $mode = $back[$i]{$mode} if $i > 0;
    }
    my (@segs, $run, $runmode);
    my $flush = sub {
        return unless defined $runmode;
        push @segs, $runmode eq 'numeric' ? make_numeric($run)
                  : $runmode eq 'alphanumeric' ? make_alphanumeric($run)
                  : make_bytes(_utf8_bytes($run));
    };
    for my $i (0 .. $#chars) {
        if (defined $runmode && $plan[$i] eq $runmode) { $run .= $chars[$i]; next }
        $flush->();
        ($run, $runmode) = ($chars[$i], $plan[$i]);
    }
    $flush->();
    return \@segs;
}

1;
