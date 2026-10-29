use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'QRSmith',
    AUTHOR           => 'Aryan Vohra',
    VERSION_FROM     => 'lib/QRSmith.pm',
    ABSTRACT         => 'Pure-Perl QR Code encoder with a Reed-Solomon codec',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.016',
    EXE_FILES        => ['bin/qrsmith'],
    PREREQ_PM        => {},
    TEST_REQUIRES    => { 'Test::More' => '0.98' },
    test             => { TESTS => 't/*.t' },
);
