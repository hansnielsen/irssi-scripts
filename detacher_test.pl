# Basic test script for detacher.pl

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
$VERSION = '0.01';
%IRSSI = (
    authors     => 'Hans Nielsen',
    contact     => 'hans@stackallocated.com',
    name        => 'Detacher Test',
    description => 'Used to test detacher.pl.',
    license     => 'Simplified BSD',
);

Irssi::signal_add("detacher attached", \&signal_detacher_attached);
Irssi::signal_add("detacher detached", \&signal_detacher_detached);

#########################################################
# VARIOUS UTILITY THINGS
#########################################################
my $detached = 1;

#########################################################
# SIGNALS
#########################################################

sub signal_detacher_attached {
    if ($detached) {
        Irssi::print("Attached!");
        $detached = 0;
    } else {
        Irssi::print("Reattached!");
    }
}

sub signal_detacher_detached {
    if ($detached) {
        Irssi::print("Redetached!");
    } else {
        Irssi::print("Detached!");
        $detached = 1;
    }
}
