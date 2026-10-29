use strict;
use warnings;
use Test::More;
use lib 'lib';
use QRSmith::BitBuffer;

my $bb = QRSmith::BitBuffer->new;
$bb->append(0b0010, 4)->append(11, 9);
is($bb->as_string, '0010000001011', 'MSB-first append');
is($bb->length, 13, 'length');
$bb->append(0, 3);
is_deeply($bb->to_bytes, [0b00100000, 0b01011000], 'to_bytes');
eval { $bb->append(8, 3) };
like($@, qr/does not fit/, 'overflow rejected');
eval { QRSmith::BitBuffer->new->append(1, 3)->to_bytes };
like($@, qr/multiple of 8/, 'partial byte rejected');
my $o = QRSmith::BitBuffer->new->append(1, 1);
is(QRSmith::BitBuffer->new->append(2, 2)->append_buffer($o)->as_string, '101', 'append_buffer');
done_testing;
