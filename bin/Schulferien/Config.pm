package Schulferien::Config;

use strict;
use warnings;
use File::Spec;

my %DEFAULTS = (
    state                   => 'BY',
    mqtt_base_topic         => 'loxberry/schulferien',
    mqtt_device_id          => 'by',
    mqtt_use_loxberry_broker => 1,
    mqtt_host               => '',
    mqtt_port               => 1883,
    mqtt_user               => '',
    mqtt_password           => '',
    poll_interval           => 21600,
    enabled                 => 1,
);

our %STATES = (
    BW => 'Baden-Württemberg',
    BY => 'Bayern',
    BE => 'Berlin',
    BB => 'Brandenburg',
    HB => 'Bremen',
    HH => 'Hamburg',
    HE => 'Hessen',
    MV => 'Mecklenburg-Vorpommern',
    NI => 'Niedersachsen',
    NW => 'Nordrhein-Westfalen',
    RP => 'Rheinland-Pfalz',
    SL => 'Saarland',
    SN => 'Sachsen',
    ST => 'Sachsen-Anhalt',
    SH => 'Schleswig-Holstein',
    TH => 'Thüringen',
);

sub cfg_path {
    my ($lb_home, $plugin_folder) = @_;
    # Stored in the data dir — guaranteed writable by the CGI and daemon user
    return File::Spec->catfile($lb_home, 'data', 'plugins', $plugin_folder, 'schulferien.cfg');
}

sub cfg_path_default {
    my ($lb_home, $plugin_folder) = @_;
    # Read-only default shipped in the plugin ZIP and installed by LoxBerry
    return File::Spec->catfile($lb_home, 'config', 'plugins', $plugin_folder, 'schulferien.cfg');
}

sub state_store {
    my ($data_dir) = @_;
    return File::Spec->catfile($data_dir, 'schulferien_state.json');
}

sub holidays_store {
    my ($data_dir) = @_;
    return File::Spec->catfile($data_dir, 'schulferien_holidays.json');
}

sub _read_cfg_file {
    my ($path, $cfg_ref) = @_;
    return unless -f $path;
    open my $fh, '<', $path or return;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*[#;]/ || $line !~ /=/;
        my ($k, $v) = split /=/, $line, 2;
        $k =~ s/^\s+|\s+$//g;
        $v //= '';
        $v =~ s/^\s+|\s+$//g;
        $cfg_ref->{$k} = $v if $k ne '';
    }
    close $fh;
}

sub normalize_poll_interval {
    my ($seconds) = @_;
    $seconds = int($seconds // 21600);
    return 21600 if $seconds < 21600;
    return $seconds;
}

sub normalize_state {
    my ($code) = @_;
    $code = uc($code // '');
    return 'BY' unless $code && exists $STATES{$code};
    return $code;
}

sub _migrate_user_data_to_data_dir {
    my ($lb_home, $plugin_folder) = @_;
    my $dir = File::Spec->catdir($lb_home, 'data', 'plugins', $plugin_folder);
    unless (-d $dir) {
        eval { require File::Path; File::Path::make_path($dir) };
        mkdir $dir unless -d $dir;
    }
    my $data_cfg = cfg_path($lb_home, $plugin_folder);
    my $def_cfg  = cfg_path_default($lb_home, $plugin_folder);
    return if -f $data_cfg || !-f $def_cfg;
    open my $in, '<', $def_cfg or return;
    open my $out, '>', $data_cfg or do { close $in; return };
    local $/;
    my $content = <$in>;
    print $out $content;
    close $in;
    close $out;
}

sub load {
    my ($lb_home, $plugin_folder) = @_;
    my %cfg = %DEFAULTS;
    _migrate_user_data_to_data_dir($lb_home, $plugin_folder);
    _read_cfg_file(cfg_path_default($lb_home, $plugin_folder), \%cfg);
    _read_cfg_file(cfg_path($lb_home, $plugin_folder), \%cfg);
    $cfg{state} = normalize_state($cfg{state});
    $cfg{poll_interval} = normalize_poll_interval($cfg{poll_interval});
    return \%cfg;
}

sub save {
    my ($lb_home, $plugin_folder, $cfg) = @_;
    my $path = cfg_path($lb_home, $plugin_folder);
    my $dir  = File::Spec->catdir($lb_home, 'data', 'plugins', $plugin_folder);

    unless (-d $dir) {
        eval { require File::Path; File::Path::make_path($dir) };
        mkdir $dir unless -d $dir;
    }

    open my $fh, '>', $path
        or return "Konfiguration konnte nicht gespeichert werden: $! ($path)";

    for my $k (sort keys %$cfg) {
        print $fh "$k=$cfg->{$k}\n";
    }
    close $fh;
    return '';  # empty string = success
}

sub state_label {
    my ($code) = @_;
    return $STATES{uc($code // '')} // $code // '';
}

1;
