#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Spec;
use POSIX qw(strftime);
use JSON::PP qw(encode_json);

my $plugin_folder = basename($FindBin::Bin);
my $bin_dir       = abs_path($FindBin::Bin);
my $lb_home       = $ENV{LBHOMEDIR} // $ENV{LB_HOME};
if (!$lb_home) {
    $lb_home = File::Spec->catdir($bin_dir, '..', '..', '..');
    $lb_home = abs_path($lb_home) || $lb_home;
}

unshift @INC, $bin_dir;

my $log_dir  = File::Spec->catdir($lb_home, 'log',  'plugins', $plugin_folder);
my $data_dir = File::Spec->catdir($lb_home, 'data', 'plugins', $plugin_folder);
my $log_file = File::Spec->catfile($log_dir, 'schulferien.log');

for ($log_dir, $data_dir) {
    mkdir $_ unless -d $_;
}

sub log_msg {
    my ($level, $msg) = @_;
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $line = "[$ts] [$level] $msg\n";
    print $line;
    if (open my $fh, '>>', $log_file) {
        print $fh $line;
        close $fh;
    }
}

sub log_info  { log_msg('INFO',  $_[0]) }
sub log_warn  { log_msg('WARN',  $_[0]) }
sub log_error { log_msg('ERROR', $_[0]) }

require Schulferien::Config;
require Schulferien::API;
require Schulferien::LoxBerryMqtt;

eval { require Net::MQTT::Simple; 1 } or do {
    log_error('Missing Perl module Net::MQTT::Simple — install libnet-mqtt-simple-perl or run: cpanm Net::MQTT::Simple');
    exit 1;
};

log_info("Schulferien MQTT Daemon starting (plugin: $plugin_folder, lb_home: $lb_home)");

sub connect_mqtt {
    my ($cfg) = @_;
    my ($mqtt, $broker_info, $err) = Schulferien::LoxBerryMqtt::connect_simple(
        use_loxberry_broker => $cfg->{mqtt_use_loxberry_broker} // 1,
        lb_home             => $lb_home,
        host                => $cfg->{mqtt_host},
        port                => $cfg->{mqtt_port},
        user                => $cfg->{mqtt_user},
        password            => $cfg->{mqtt_password},
    );
    return ($mqtt, $broker_info, $err);
}

sub publish_topics {
    my ($mqtt, $avail_topic, $data_topic, $payload) = @_;
    my $json = encode_json($payload);

    eval { $mqtt->retain($avail_topic, 'online') };
    if ($@) {
        return "availability publish failed: $@";
    }

    eval { $mqtt->retain($data_topic, $json) };
    if ($@) {
        return "data publish failed: $@";
    }

    log_info("Published retain $avail_topic=online");
    log_info("Published retain $data_topic=$json");
    return '';
}

while (1) {
    my $cfg = Schulferien::Config::load($lb_home, $plugin_folder);

    unless ($cfg->{enabled}) {
        log_info('Plugin disabled — sleeping 60s');
        sleep 60;
        next;
    }

    my $state         = Schulferien::Config::normalize_state($cfg->{state});
    my $base_topic    = $cfg->{mqtt_base_topic} // 'loxberry/schulferien';
    my $slug          = $cfg->{mqtt_device_id}  // lc($state);
    my $data_topic    = "$base_topic/$slug/data";
    my $avail_topic   = "$base_topic/$slug/availability";
    my $poll_interval = Schulferien::Config::normalize_poll_interval($cfg->{poll_interval});

    my $mqtt;
    my $broker_info;
    my $mqtt_failures = 0;
    while (!$mqtt) {
        ($mqtt, $broker_info, my $err) = connect_mqtt($cfg);
        if (!$mqtt) {
            $mqtt_failures++;
            my $addr = $broker_info ? $broker_info->{address} : 'unknown';
            if ($mqtt_failures == 1 || $mqtt_failures % 6 == 0) {
                log_error("MQTT connection failed ($addr): $err");
            }
            sleep 10;
        }
    }

    log_info("State=$state topic=$data_topic interval=${poll_interval}s");
    log_info("MQTT connected to $broker_info->{address} (source: $broker_info->{source})");

    my $last_date  = '';
    my $cfg_mtime  = (stat(Schulferien::Config::cfg_path($lb_home, $plugin_folder)))[9] // 0;
    my $reload_cfg = 0;

    while (!$reload_cfg) {
        my $today = Schulferien::API::today_iso();
        log_info("Fetching holidays for $state (today: $today)");

        my ($status, $err) = Schulferien::API::build_status_for_state($state);
        if ($err && !$status) {
            log_error("API fetch failed: $err");
            eval { $mqtt->retain($avail_topic, 'offline') };
            log_warn("MQTT publish failed: $@") if $@;
            sleep 300;
            eval { $mqtt->retain($avail_topic, 'online') };
            log_warn("MQTT publish failed: $@") if $@;
        } else {
            log_warn("Partial API error: $err") if $err;
            my $payload = Schulferien::API::build_mqtt_payload($status);
            my $pub_err = publish_topics($mqtt, $avail_topic, $data_topic, $payload);
            if ($pub_err) {
                log_warn($pub_err);
                $reload_cfg = 1;
                last;
            }

            my $path = Schulferien::Config::state_store($data_dir);
            if (open my $fh, '>', $path) {
                print $fh encode_json($status);
                close $fh;
            }
        }

        $last_date = $today;

        my $slept = 0;
        while ($slept < $poll_interval && !$reload_cfg) {
            sleep 60;
            $slept += 60;

            if (Schulferien::API::today_iso() ne $last_date) {
                log_info('Date changed — refreshing');
                last;
            }

            my $cur_mtime = (stat(Schulferien::Config::cfg_path($lb_home, $plugin_folder)))[9] // 0;
            if ($cur_mtime != $cfg_mtime) {
                log_info('Config changed — reloading');
                $reload_cfg = 1;
                last;
            }
        }
    }

    undef $mqtt;
    sleep 1;
}
