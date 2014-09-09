# Provides Pushover notifications for PMs and hilights.
#
# Requires the ability to make HTTPS requests with LWP.
#   On Debian / Ubuntu:
#     $ sudo apt-get install libwww-perl libio-socket-ssl-perl
#   On other systems with CPAN, either command should work:
#     $ sudo cpan -i IO::Socket::SSL
#     $ sudo cpan -i Crypt::SSLeay
#
# Works with detacher.pl if it is currently loaded.

use strict;
use vars qw($VERSION %IRSSI);
use LWP::UserAgent;

use Irssi;
$VERSION = '0.01';
%IRSSI = (
    authors     => 'Hans Nielsen',
    contact     => 'hans@stackallocated.com',
    name        => 'Pushover for irssi',
    description => 'Sends push notifications for irssi events to Pushover, which sends them to phones and desktops.',
    license     => 'Simplified BSD',
);

Irssi::settings_add_bool("pushover", "pushover", 0);
Irssi::settings_add_str ("pushover", "pushover_api_key", "");
Irssi::settings_add_str ("pushover", "pushover_user_key", "");
Irssi::settings_add_str ("pushover", "pushover_user_device", "");

Irssi::settings_add_int ("pushover", "pushover_timeout", 10);
Irssi::settings_add_int ("pushover", "pushover_max_messages", 5);

Irssi::command_bind("pushover on",       \&pushover_on,       "Pushover");
Irssi::command_bind("pushover off",      \&pushover_off,      "Pushover");
Irssi::command_bind("pushover",          \&subcmd_handler,    "Pushover");
Irssi::command_bind("help",              \&help_pushover);

Irssi::signal_add("print text",      \&signal_print_text);
Irssi::signal_add("message private", \&signal_message_private);

Irssi::signal_add("proxy client connected",    \&signal_proxy_client_connected);
Irssi::signal_add("proxy client disconnected", \&signal_proxy_client_disconnected);
Irssi::signal_add("detacher attached",         \&signal_detacher_attached);
Irssi::signal_add("detacher detached",         \&signal_detacher_detached);

Irssi::signal_add("gui key pressed",      \&reset_messages);
Irssi::signal_add("message own_public",   \&reset_messages);
Irssi::signal_add("message own_private",  \&reset_messages);
Irssi::signal_add("message own_nick",     \&reset_messages);

Irssi::signal_add("setup changed", \&signal_setup_changed);

#########################################################
# VARIOUS UTILITY THINGS
#########################################################
my %proxies = ();
my $detached = 1;
my $sent_messages = 0;
my $enabled = 0;

sub should_send_pushover {
    my ($chatnet) = @_;

    return unless $sent_messages < Irssi::settings_get_int("pushover_max_messages");
    return unless $enabled;
    return unless $detached;
    return if defined $proxies{$chatnet};

    return 1;
}

sub reset_messages {
    $sent_messages = 0;
}

sub disable_pushover {
    $enabled = 0;
    Irssi::settings_set_bool("pushover", 0);
}

sub enable_pushover {
    $enabled = 1;
    Irssi::settings_set_bool("pushover", 1);
}

#########################################################
# PUSHOVER SERVICE
#########################################################
my @queued = ();
my $queue_timeout;
my $api_key;
my $user_key;
my $user_device;

my $ua = LWP::UserAgent->new();
$ua->agent("pushover-irssi/$VERSION");
$ua->env_proxy();
$ua->timeout(4);

my $message_url  = "https://api.pushover.net/1/messages.json";
my $validate_url = "https://api.pushover.net/1/users/validate.json";

sub check_pushover_validity {
    $api_key = Irssi::settings_get_str("pushover_api_key");
    $user_key = Irssi::settings_get_str("pushover_user_key");
    $user_device = Irssi::settings_get_str("pushover_user_device");

    my %req = (
        "token"   => $api_key,
        "user"    => $user_key,
    );

    if (defined $user_device and length $user_device) {
        $req{"device"} = $user_device;
    }

    my $ret = $ua->post($validate_url, \%req);
    my $valid = $ret->{"_rc"} eq "200";

    if (!$valid) {
        Irssi::active_win()->print("WARNING: Pushover settings didn't validate, disabling");
        disable_pushover;
    }

    return $valid;
}

sub send_pushover {
    my ($title, $msg, $priority) = @_;

    if ($sent_messages == Irssi::settings_get_int("pushover_max_messages") - 1) {
        $title = "Final notification: " . $title;
    }

    my %req = (
        "token"   => $api_key,
        "user"    => $user_key,
        "title"   => $title,
        "message" => $msg,
    );

    if (defined $priority and length $priority) {
        $req{"priority"} = $priority;
    }

    my $device = Irssi::settings_get_str("pushover_user_device");
    if (defined $device and length $device) {
        $req{"device"} = $device;
    }

    my $ret = $ua->post($message_url, \%req);

    if ($ret->{"_rc"} ne "200") {
        Irssi::print("Failed to make Pushover request! '" . $ret->{"_content"} . "'");
        return 0;
    }

    $sent_messages++;

    return 1;
}

sub send_queued_pushovers {
    my $events = scalar @queued;

    if ($events == 0) {
        Irssi::timeout_remove($queue_timeout);
        $queue_timeout = undef;
        return;
    } elsif ($events == 1) {
        send_pushover(@{shift @queued});
        return;
    }

    my @titles;
    foreach my $notification (@queued) {
        push @titles, $notification->[0];
    }
    send_pushover("$events new IRC events", join("\n", @titles));

    @queued = ();
}

sub enqueue_pushover {
    my ($title, $msg, $priority) = @_;

    if ($queue_timeout) {
        push @queued, [$title, $msg, $priority];
    } else {
        send_pushover($title, $msg, $priority);

        my $t = Irssi::settings_get_int("pushover_timeout") * 1000;
        $queue_timeout = Irssi::timeout_add($t, \&send_queued_pushovers, undef);
    }
}

#########################################################
# SIGNALS
#########################################################

sub signal_print_text {
    my ($dest, $newstr, $stripped) = @_;

    # if we're not connected to a server, we can't be hilighted
    my $server = $dest->{"server"};
    return unless defined $server;

    return unless should_send_pushover($server->{"chatnet"});

    if ($dest->{'level'} & Irssi::MSGLEVEL_HILIGHT) {
        enqueue_pushover("Hilighted in $server->{'chatnet'}/$dest->{'target'}", $stripped);
    }
}

sub signal_message_private {
    my ($server, $msg, $nick, $address) = @_;

    return unless should_send_pushover($server->{"chatnet"});

    enqueue_pushover("PM from $nick", "$nick on $server->{'chatnet'} said '$msg'");
}

sub signal_proxy_client_connected {
    my ($client) = @_;

    my $ircnet = $client->{"ircnet"};
    if (defined $proxies{$ircnet}) {
        $proxies{$ircnet}++;
    } else {
        $proxies{$ircnet} = 1;
    }
}

sub signal_proxy_client_disconnected {
    my ($client) = @_;

    my $ircnet = $client->{"ircnet"};
    if (defined $proxies{$ircnet}) {
        $proxies{$ircnet}--;
        if ($proxies{$ircnet} == 0) {
            delete $proxies{$ircnet};
        }
    } else {
        Irssi::print("WARNING: Proxy disconnect for an unknown ircnet?!");
    }
}

sub signal_detacher_attached {
    $detached = 0;
}

sub signal_detacher_detached {
    $detached = 1;
    reset_messages;
}

sub signal_setup_changed {
    if (Irssi::settings_get_int("pushover_timeout") < 1) {
        Irssi::settings_set_int("pushover_timeout", 10);
    }
    if (Irssi::settings_get_int("pushover_max_messages") < 1) {
        Irssi::settings_set_int("pushover_max_messages", 5);
    }

    if (!Irssi::settings_get_bool("pushover")) {
        disable_pushover;
        return;
    }

    if ($api_key ne Irssi::settings_get_str("pushover_api_key")
      || $user_key ne Irssi::settings_get_str("pushover_user_key")
      || $user_device ne Irssi::settings_get_str("pushover_user_device")
      || !$enabled) {
        return if !check_pushover_validity();
    }

    enable_pushover;
}

#########################################################
# COMMANDS
#########################################################

sub subcmd_handler {
    my ($data, $server, $item) = @_;
    $data =~ s/\s+$//g;

    if ($data eq "") {
        Irssi::print("Pushover notifications are currently " . ($enabled ? "on" : "off"));
    } else {
        Irssi::command_runsub("pushover", $data, $server, $item);
    }
}

sub pushover_on {
    return if $enabled;

    return unless check_pushover_validity();

    Irssi::print("Pushover enabled");
    enable_pushover;
}

sub pushover_off {
    return if !$enabled;

    Irssi::print("Pushover disabled");
    disable_pushover;
}

sub help_pushover {
    my ($data, $server, $item) = @_;

    return unless $data =~ /^\s*pushover\s*$/si;

    my $help = <<EOF;
Provides Pushover notifications for PMs and hilights.

To use it, you must have signed up for Pushover:
  https://pushover.net
Set your user key (replacing 8lHNrC... with your own):

    /SET pushover_user_key 8lHNrC...

Register a new application to get an API key:
  https://pushover.net/apps/build
Any name (such as "irssi") is fine.
Set the API key (replacing vRjlFg... with your own):

    /SET pushover_api_key vRjlFg...

Once those two keys are set up, enable Pushover. If your
settings aren't valid, you'll be alerted to that. If you
don't get a warning, then everything is good to go.

    /SET pushover on

To turn it off:

    /SET pushover off

To send notifications only to a specific device:

    /SET pushover_user_device foo

By default, a maximum of five messages with at least ten
seconds between them will be sent. To change that:

    /SET pushover_max_messages 7
    /SET pushover_timeout 15
EOF

    Irssi::print($help);
    Irssi::signal_stop;
}

#########################################################
# THE THING THAT RUNS AT STARTUP
#########################################################
signal_setup_changed;
if ($enabled) {
    Irssi::print("Pushover enabled");
}
