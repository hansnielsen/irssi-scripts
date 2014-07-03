use strict;
use vars qw($VERSION %IRSSI);

use File::Spec::Functions qw(catfile);
use File::stat;
use Fcntl ":mode";

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
my %internal = ();

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
        return setup_screen();
    } elsif ($type eq "tmux") {
        return setup_tmux();
    } elsif ($type eq "dtach") {
        return setup_dtach();
    } elsif ($type eq "" || $type eq "auto") {
        return auto_detacher_finder();
    }

    Irssi::print("WARNING: Detacher type '$type' is unknown!");
    return undef;
}

sub auto_detacher_finder {
    if (defined $ENV{"STY"}) {
        return setup_screen();
    } elsif (defined $ENV{"TMUX"}) {
        return setup_tmux();
    }

    # because dtach doesn't mess with the environment, just try it
    my $ret = setup_dtach();
    return $ret if defined $ret;

    return undef;
}

sub check_exec_socket {
    my $s = stat $internal{"exec_socket"};
    return ($s->mode & S_IXUSR) != 0;
}

sub setup_screen {
    # gross, but only consistent way to get sockdir
    `screen -ls` =~ /^\d+ Sockets? in (\S+)\.$/m;
    my $socketpath = catfile($1, $ENV{"STY"});
    if (! -p $socketpath) {
        Irssi::print("WARNING: Screen socket doesn't exist or isn't a socket!");
        return undef;
    }
    $internal{"exec_socket"} = $socketpath;

    return \&check_exec_socket;
}

sub setup_tmux {
    my ($socketpath, ) = split ",", $ENV{"TMUX"};
    if (! -S $socketpath) {
        Irssi::print("WARNING: tmux socket doesn't exist or isn't a socket!");
        return undef;
    }
    $internal{"exec_socket"} = $socketpath;

    return \&check_exec_socket;
}

sub setup_dtach {
    return undef;
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
