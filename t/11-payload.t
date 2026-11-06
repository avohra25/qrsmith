use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use QRSmith;
use QRSmith::Payload qw(wifi vcard mailto sms geo url);

# --- wifi ---
is(wifi(ssid => 'home', password => 'hunter22', security => 'WPA'),
   'WIFI:T:WPA;S:home;P:hunter22;;', 'wifi basic WPA');
is(wifi(ssid => 'cafe', security => 'nopass'),
   'WIFI:T:nopass;S:cafe;;', 'wifi open network');
is(wifi(ssid => 'x', password => 'y', security => 'WEP', hidden => 1),
   'WIFI:T:WEP;S:x;P:y;H:true;;', 'wifi WEP hidden');
is(wifi(ssid => 'a;b,c\\d"e', password => 'p;q'),
   'WIFI:T:WPA;S:a\;b\,c\\\\d\"e;P:p\;q;;', 'wifi escapes ; , \\ "');
eval { wifi(password => 'x') }; like($@, qr/ssid required/, 'wifi needs ssid');
eval { wifi(ssid => 'x', security => 'TKIP') }; like($@, qr/security must be/, 'wifi bad security');

# --- vcard ---
my $vc = vcard(name => 'Ada Lovelace', org => 'Analytical Engines',
               phone => '+1-555-0100', email => 'ada@example.com',
               url => 'https://example.com', note => "note; with, specials");
like($vc, qr/\ABEGIN:VCARD\nVERSION:3\.0\n/, 'vcard header');
like($vc, qr/FN:Ada Lovelace/, 'vcard FN');
like($vc, qr/N:;Ada Lovelace;;;/, 'vcard N from display name');
like($vc, qr/ORG:Analytical Engines/, 'vcard ORG');
like($vc, qr/TEL:\+1-555-0100/, 'vcard TEL');
like($vc, qr/EMAIL:ada\@example\.com/, 'vcard EMAIL');
like($vc, qr/URL:https:\/\/example\.com/, 'vcard URL');
like($vc, qr/NOTE:note\\; with\\, specials/, 'vcard NOTE escapes');
like($vc, qr/END:VCARD\n\z/, 'vcard footer');
my $vc2 = vcard(name => 'Lovelace, Ada', phone => '555');
like($vc2, qr/N:Lovelace;Ada;;;/, 'vcard parses Last, First');
eval { vcard(org => 'x') }; like($@, qr/name/, 'vcard needs name');

# --- mailto ---
is(mailto(email => 'a@b.co'), 'mailto:a@b.co', 'mailto bare');
is(mailto(email => 'a@b.co', subject => 'Hi there', body => 'line 1 & 2'),
   'mailto:a@b.co?subject=Hi%20there&body=line%201%20%26%202', 'mailto escapes');
is(mailto(email => 'a@b.co', subject => 'cafés'),
   'mailto:a@b.co?subject=caf%C3%A9s', 'mailto UTF-8 percent-encodes');
eval { mailto(subject => 'x') }; like($@, qr/email required/, 'mailto needs email');

# --- sms ---
is(sms(number => '+1 (555) 010-0', body => 'hello'),
   'SMSTO:+15550100:hello', 'sms SMSTO form strips punctuation');
is(sms(number => '5550100', body => 'hi there', style => 'sms'),
   'sms:5550100?body=hi%20there', 'sms URI form');
is(sms(number => '555'), 'SMSTO:555:', 'sms empty body');
eval { sms(body => 'x') }; like($@, qr/number required/, 'sms needs number');

# --- geo ---
is(geo(lat => 37.7749, lon => -122.4194), 'geo:37.7749,-122.4194', 'geo basic');
is(geo(lat => 0, lon => 0, query => 'Null Island'),
   'geo:0,0?q=Null%20Island', 'geo with query');
eval { geo(lat => 100, lon => 0) }; like($@, qr/lat out of range/, 'geo lat range');
eval { geo(lat => 0, lon => 200) }; like($@, qr/lon out of range/, 'geo lon range');
eval { geo(lat => 'x', lon => 0) }; like($@, qr/lat must be numeric/, 'geo lat numeric');

# --- url ---
is(url('https://example.com/a'), 'https://example.com/a', 'url passthrough');
is(url('example.com/path'), 'https://example.com/path', 'url adds https');
is(url('  ftp://x  '), 'ftp://x', 'url trims');
eval { url('') }; like($@, qr/url required/, 'url rejects empty');

# --- round-trip encode: payloads become real QR symbols ---
my @payloads = (
    wifi(ssid => 'lab', password => 's3cret!', security => 'WPA'),
    vcard(name => 'Test User', email => 't@example.com'),
    mailto(email => 't@example.com', subject => 'QR'),
    sms(number => '5550100', body => 'ping'),
    geo(lat => 1.5, lon => 2.5),
    url('https://github.com/avohra25/qrsmith'),
);
for my $p (@payloads) {
    my $qr = QRSmith->encode($p, ecl => 'M');
    ok($qr->version >= 1 && $qr->version <= 40, 'encodes to a valid version');
    ok($qr->size == 4 * $qr->version + 17, 'size matches version');
    ok($qr->mask =~ /^[0-7]$/, 'mask 0..7');
}

# Thin encode_payload wrapper
my $w = wifi(ssid => 'x', password => 'y');
my $qr = QRSmith->encode_payload($w, ecl => 'Q', boost => 0);
isa_ok($qr, 'QRSmith');
is($qr->ecl, 'Q', 'encode_payload honours ecl');
ok($qr->version >= 1, 'encode_payload builds a symbol');

done_testing;
