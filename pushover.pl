use strict;
use vars qw($VERSION %IRSSI);

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

Irssi::command_bind("pushover on",  \&pushover_on,    "Pushover");
Irssi::command_bind("pushover off", \&pushover_off,   "Pushover");
Irssi::command_bind("pushover",     \&subcmd_handler, "Pushover");

sub subcmd_handler {
    my ($data, $server, $item) = @_;
    $data =~ s/\s+$//g;
    Irssi::command_runsub("pushover", $data, $server, $item);
}

sub pushover_on {
    Irssi::print("Pushover enabled") unless Irssi::settings_get_bool("pushover");
    Irssi::settings_set_bool("pushover", 1);
}

sub pushover_off {
    Irssi::print("Pushover disabled") unless !Irssi::settings_get_bool("pushover");
    Irssi::settings_set_bool("pushover", 0);
}
