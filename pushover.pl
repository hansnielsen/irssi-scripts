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

Irssi::command_bind("pushover on",       \&pushover_on,       "Pushover");
Irssi::command_bind("pushover off",      \&pushover_off,      "Pushover");
Irssi::command_bind("pushover validate", \&pushover_validate, "Pushover");
Irssi::command_bind("pushover",          \&subcmd_handler,    "Pushover");

Irssi::signal_add("print text",      \&signal_print_text);
Irssi::signal_add("message private", \&signal_message_private);

Irssi::signal_add("proxy client connected",    \&signal_proxy_client_connected);
Irssi::signal_add("proxy client disconnected", \&signal_proxy_client_disconnected);

#########################################################
# VARIOUS UTILITY THINGS
#########################################################
my %proxies = ();

sub pushover_enabled {
    return Irssi::settings_get_bool("pushover");
}

#########################################################
# PUSHOVER SERVICE
#########################################################
my $ua = LWP::UserAgent->new();
$ua->agent("pushover-irssi/$VERSION");
$ua->env_proxy();
$ua->timeout(4);

my $message_url  = "https://api.pushover.net/1/messages.json";
my $validate_url = "https://api.pushover.net/1/users/validate.json";

sub check_pushover_validity {
    my %req = (
        "token"   => Irssi::settings_get_str("pushover_api_key"),
        "user"    => Irssi::settings_get_str("pushover_user_key"),
    );

    my $device = Irssi::settings_get_str("pushover_user_device");
    if (defined $device and length $device) {
        $req{"device"} = $device;
    }

    my $ret = $ua->post($validate_url, \%req);

    return $ret->{"_rc"} eq "200";
}

sub send_pushover_notification {
    my ($title, $msg, $priority) = @_;

    my %req = (
        "token"   => Irssi::settings_get_str("pushover_api_key"),
        "user"    => Irssi::settings_get_str("pushover_user_key"),
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

    return 1;
}

#########################################################
# SIGNALS
#########################################################

sub signal_print_text {
    return unless pushover_enabled;
    my ($dest, $newstr, $stripped) = @_;

    if ($dest->{'level'} & Irssi::MSGLEVEL_HILIGHT) {
	send_pushover_notification("Hilighted in $dest->{'target'}", $stripped);
    }
}

sub signal_message_private {
    return unless pushover_enabled;
    my ($server, $msg, $nick, $address) = @_;

    send_pushover_notification("PM from $nick", "$nick on $server->{'tag'} said '$msg'");
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

#########################################################
# COMMANDS
#########################################################

sub subcmd_handler {
    my ($data, $server, $item) = @_;
    $data =~ s/\s+$//g;
    Irssi::command_runsub("pushover", $data, $server, $item);
}

sub pushover_validate {
    my $ret = check_pushover_validity();
    if ($ret) {
        Irssi::print("Pushover settings validated!");
    } else {
        Irssi::print("Pushover settings failed to validate!");
    }
}

Irssi::command_bind("help", sub {
    if ($_[0] eq "pushover validate") {
        Irssi::print("", Irssi::MSGLEVEL_CLIENTCRAP);
        Irssi::print("PUSHOVER VALIDATE", Irssi::MSGLEVEL_CLIENTCRAP);
        Irssi::print("", Irssi::MSGLEVEL_CLIENTCRAP);
        Irssi::print("Tests the app API key, user ID, and user device against the Pushover server to make sure it is configured properly.", Irssi::MSGLEVEL_CLIENTCRAP);
        Irssi::signal_stop();
    }
});

sub pushover_on {
    Irssi::print("Pushover enabled") unless pushover_enabled;
    Irssi::settings_set_bool("pushover", 1);
}

sub pushover_off {
    Irssi::print("Pushover disabled") unless !pushover_enabled;
    Irssi::settings_set_bool("pushover", 0);
}
