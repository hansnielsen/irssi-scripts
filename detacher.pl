# This script provides detach / attach events for a terminal detacher.
#
# To use it, register for 'detacher detached' and 'detacher attached'.
# For example:
#
#   Irssi::signal_add("detacher attached", \&sub_to_handle_attaching);
#
# The detach check interval is set by "detacher_check_interval" and
# defaults to five seconds. It can be set in one second increments.
#
# Whether you're using screen / tmux / dtach should be autodetected.
# If it isn't, set "detacher_type" to "screen" / "tmux" / "dtach" and
# it will attempt to use that type.
#
# If you are using dtach, you need to have the `lsof` utility installed.

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

Irssi::settings_add_int("misc", "detacher_check_interval", 5);
Irssi::settings_add_str("misc", "detacher_type", "");

Irssi::signal_register({"detacher attached" => [], "detacher detached" => []});

Irssi::signal_add("setup changed", \&signal_setup_changed);

my $timeout;
my $detacher_check;
my $state = 0; # default is detached

#########################################################
# THE THING WHICH IS RESPONSIBLE FOR IT ALL
#########################################################
signal_setup_changed();

#########################################################
# DETACHER RELATED JUNK
#########################################################
sub determine_detacher {
    my $type = (Irssi::settings_get_str("detacher_type"));

    if ($type eq "screen") {
        return setup_screen();
    } elsif ($type eq "tmux") {
        return setup_tmux();
    } elsif ($type eq "dtach") {
        return setup_dtach(1);
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
    my ($socket) = @_;

    my $s = stat $socket;
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
    return curry(\&check_exec_socket, $socketpath);
}

sub setup_tmux {
    my ($socketpath, ) = split ",", $ENV{"TMUX"};
    if (! -S $socketpath) {
        Irssi::print("WARNING: tmux socket doesn't exist or isn't a socket!");
        return undef;
    }
    return curry(\&check_exec_socket, $socketpath);
}

sub setup_dtach {
    my ($warn) = @_;

    my $pid = $$;
    my $ret;
    do {
        my $processname = `lsof -F c -U -a -p $pid`;
        if ($processname =~ /^cdtach$/m) {
            return curry(\&check_dtach, $pid);
        }

        $ret = `lsof -F R -p $pid` =~ /^R(?<pid>.+)$/m;
        $pid = $+{pid};
    } while ($ret);

    Irssi::print("WARNING: Couldn't get PID of dtach process") if $warn;
    return undef;
}

sub check_dtach {
    my ($dtach_pid) = @_;

    my $sockets = `lsof -F n -U -a -p $dtach_pid`;

    my $count = 0;
    while ($sockets =~ /^n.+$/gm) {
        $count++;
    }

    return $count > 1;
}

#########################################################
# VARIOUS UTILITY THINGS
#########################################################
sub curry {
    my $f = shift;
    my $args = \@_;
    sub {
        $f->(@$args, @_);
    }
}

sub stop_timeout {
    Irssi::timeout_remove($timeout);
    $timeout = undef;
}

sub start_timeout {
    stop_timeout();

    my $secs = Irssi::settings_get_int("detacher_check_interval");
    if ($secs < 1) {
        Irssi::print("WARNING: Detacher check interval out of bounds, set to 5 seconds");
        Irssi::settings_set_int("detacher_check_interval", 5);
    }

    my $msecs = Irssi::settings_get_int("detacher_check_interval") * 1000;
    $timeout = Irssi::timeout_add($msecs, \&detacher_timeout, undef);
}

sub detacher_timeout {
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

    # emit this to make sure scripts relying on this aren't left hanging
    Irssi::signal_emit("detacher detached");
}

#########################################################
# SIGNALS
#########################################################
sub signal_setup_changed {
    stop_timeout();

    $detacher_check = determine_detacher();
    if ($detacher_check) {
        detacher_timeout();
        start_timeout();
    }
}
