use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
$VERSION = '0.01';
%IRSSI = (
    authors     => 'Hans Nielsen',
    contact     => 'hans@stackallocated.com',
    name        => 'Terminal Detach Detector',
    description => 'Determines when a terminal is attached or detached, and sends an event when this happens.',
    license     => 'Simplified BSD',
);

Irssi::settings_add_int("misc", "detached_check_interval", 5);
Irssi::settings_add_str("misc", "detached_type", "");

Irssi::signal_register({"detacher attached" => [], "detacher detached" => []});

Irssi::signal_add("setup changed", \&signal_setup_changed);

my $timeout;
my $detacher_check;
my $state = 0;

#########################################################
# THE THING WHICH IS RESPONSIBLE FOR IT ALL
#########################################################
signal_setup_changed();

#########################################################
# DETACHER RELATED JUNK
#########################################################
sub determine_detacher {
    my $type = (Irssi::settings_get_str("detached_type"));

    if ($type eq "screen") {
        return \&check_screen;
    } elsif ($type eq "tmux") {
        return \&check_tmux;
    } elsif ($type eq "dtach") {
        return \&check_dtach;
    } elsif ($type eq "" || $type eq "auto") {
        return auto_detacher_finder();
    }

    Irssi::print("WARNING: Detacher type '$type' is unknown!");
    return undef;
}

sub auto_detacher_finder {
    return undef;
}

sub check_screen {
  return 0;
}

sub check_tmux {
  return 0;
}

sub check_dtach {
  return 0;
}

#########################################################
# VARIOUS UTILITY THINGS
#########################################################
sub stop_timeout {
    Irssi::timeout_remove($timeout);
    $timeout = undef;
}

sub start_timeout {
    stop_timeout();

    my $secs = Irssi::settings_get_int("detached_check_interval");
    if ($secs < 1) {
        Irssi::print("WARNING: Detached check interval out of bounds, set to 5 seconds");
        Irssi::settings_set_int("detached_check_interval", 5);
    }

    my $msecs = Irssi::settings_get_int("detached_check_interval") * 1000;
    $timeout = Irssi::timeout_add($msecs, \&detached_timeout, undef);
}

sub detached_timeout {
    my $ret = $detacher_check->();
    if ($ret != $state) {
        if ($ret) {
            Irssi::signal_emit("detacher attached");
        } else {
            Irssi::signal_emit("detacher detached");
        }

        $state = $ret;
    }
}

sub UNLOAD {
    stop_timeout();
}

#########################################################
# SIGNALS
#########################################################
sub signal_setup_changed {
    stop_timeout();

    $detacher_check = determine_detacher();
    if ($detacher_check) {
        detached_timeout();
        start_timeout();
    }
}
