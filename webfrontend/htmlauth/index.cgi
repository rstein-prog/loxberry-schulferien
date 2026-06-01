#!/usr/bin/env perl
use strict;
use warnings;
use CGI qw(:standard);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use File::Spec;
use JSON::PP qw(encode_json decode_json);

# ── Resolve paths ─────────────────────────────────────────────────────────────

my $SCRIPT_DIR = dirname(abs_path(__FILE__));
my $LB_HOME    = $ENV{LBHOMEDIR} // $ENV{LB_HOME};
if (!$LB_HOME) {
    $LB_HOME = File::Spec->catdir($SCRIPT_DIR, '..', '..', '..', '..');
    $LB_HOME = abs_path($LB_HOME) || $LB_HOME;
}

my $PLUGIN_FOLDER = 'schulferien';
if ($SCRIPT_DIR =~ m{/htmlauth/plugins/([^/]+)$}) {
    $PLUGIN_FOLDER = $1;
} elsif ($ENV{LBPPLUGINDIR}) {
    $PLUGIN_FOLDER = $ENV{LBPPLUGINDIR};
}

my $BIN_DIR    = File::Spec->catfile($LB_HOME, 'bin',    'plugins', $PLUGIN_FOLDER);
my $DATA_DIR   = File::Spec->catfile($LB_HOME, 'data',   'plugins', $PLUGIN_FOLDER);
my $LOG_FILE   = File::Spec->catfile($LB_HOME, 'log',    'plugins', $PLUGIN_FOLDER, 'schulferien.log');
my $SCRIPT_URL = $ENV{SCRIPT_NAME} // 'index.cgi';

unshift @INC, $BIN_DIR, File::Spec->catfile($LB_HOME, 'libs', 'perllib');

require Schulferien::Config;
require Schulferien::API;
require Schulferien::LoxBerryMqtt;
require Schulferien::Lang;
require Schulferien::WebUI;

if ($LB_HOME && $PLUGIN_FOLDER) {
    $ENV{lbptemplatedir} = File::Spec->catdir($LB_HOME, 'templates', 'plugins', $PLUGIN_FOLDER);
}
my $L = Schulferien::Lang::load($LB_HOME, $PLUGIN_FOLDER);

mkdir $DATA_DIR unless -d $DATA_DIR;

my $q   = CGI->new;
my $tab = scalar($q->param('tab') // 'config');
$tab = 'config' if $tab !~ /^(config|monitor)$/;

my $cfg = Schulferien::Config::load($LB_HOME, $PLUGIN_FOLDER);

# ── Plugin URL for icons ──────────────────────────────────────────────────────

my $plugin_url = '';
{
    my $uri = $SCRIPT_URL;
    $uri =~ s|/index\.cgi$||;
    $plugin_url = $uri;
}

# ── Actions ───────────────────────────────────────────────────────────────────

my ($message, $msg_type) = ('', 'info');

if ($q->request_method eq 'POST' && defined $q->param('save_config')) {
    my $old_state = Schulferien::Config::normalize_state($cfg->{state});
    my %new = (
        state                    => Schulferien::Config::normalize_state(scalar($q->param('state') // 'BY')),
        mqtt_base_topic          => scalar($q->param('mqtt_base_topic') // 'loxberry/schulferien'),
        mqtt_device_id           => lc(scalar($q->param('mqtt_device_id') // 'by')),
        mqtt_use_loxberry_broker => ($q->param('mqtt_use_loxberry_broker') ? 1 : 0),
        mqtt_host                => scalar($q->param('mqtt_host')     // ''),
        mqtt_port                => scalar($q->param('mqtt_port')     // 1883),
        mqtt_user                => scalar($q->param('mqtt_user')     // ''),
        mqtt_password            => scalar($q->param('mqtt_password') // ''),
        poll_interval            => Schulferien::Config::normalize_poll_interval(
            int(scalar($q->param('poll_interval_hours') // 6)) * 3600
        ),
        enabled                  => ($q->param('enabled') ? 1 : 0),
    );
    $new{poll_interval} = Schulferien::Config::normalize_poll_interval($new{poll_interval});
    $new{mqtt_device_id} = lc($new{state}) if $new{state} ne $old_state;

    my $save_err = Schulferien::Config::save($LB_HOME, $PLUGIN_FOLDER, \%new);
    if ($save_err) {
        $message  = Schulferien::Lang::format($L, 'ACTION.SAVE_ERROR', error => $save_err);
        $msg_type = 'error';
    } else {
        $cfg      = Schulferien::Config::load($LB_HOME, $PLUGIN_FOLDER);
        $message  = Schulferien::Lang::t($L, 'ACTION.SAVED');
        $msg_type = 'success';

        my ($status, $fetch_err) = eval { Schulferien::API::build_status_for_state($cfg->{state}) };
        if ($@) {
            $message .= Schulferien::Lang::t($L, 'ACTION.APPEND_HOLIDAYS_FAIL');
        } elsif ($status) {
            my $mqtt_err = _write_state_and_publish($cfg, $status, $DATA_DIR, $LB_HOME, $L);
            my $state_name = Schulferien::Config::state_label($cfg->{state});
            $message .= Schulferien::Lang::format($L, 'ACTION.APPEND_HOLIDAYS_OK', state_name => $state_name);
            $message .= Schulferien::Lang::format($L, 'ACTION.APPEND_PART', msg => $fetch_err) if $fetch_err;
            if ($mqtt_err) {
                $message .= Schulferien::Lang::format($L, 'ACTION.APPEND_MQTT', msg => $mqtt_err);
                $msg_type = 'error' if $msg_type eq 'success';
            }
        } elsif ($fetch_err) {
            $message .= Schulferien::Lang::format($L, 'ACTION.APPEND_HOLIDAYS_FAIL_DETAIL', error => $fetch_err);
        }
    }
    $tab = 'config';

} elsif ($q->request_method eq 'POST' && defined $q->param('refresh_now')) {
    my ($status, $err) = eval { Schulferien::API::build_status_for_state($cfg->{state}) };
    if ($@ || (!$status && $err)) {
        $message  = Schulferien::Lang::format($L, 'ACTION.API_ERROR', error => ($@ || $err || 'unknown'));
        $msg_type = 'error';
    } else {
        my $mqtt_err = _write_state_and_publish($cfg, $status, $DATA_DIR, $LB_HOME, $L);

        my $is_hol = $status->{is_holiday}
            ? Schulferien::Lang::t($L, 'ACTION.YES')
            : Schulferien::Lang::t($L, 'ACTION.NO');
        my $next   = $status->{next_name} // '';
        my $ndays  = $status->{next_days}  // '';
        $message   = Schulferien::Lang::format($L, 'ACTION.REFRESH_OK', is_hol => $is_hol);
        $message  .= Schulferien::Lang::format($L, 'ACTION.REFRESH_NEXT', next => $next, days => $ndays) if $next;
        $msg_type  = 'success';
        $message  .= Schulferien::Lang::format($L, 'ACTION.APPEND_PART', msg => $err) if $err;
        if ($mqtt_err) {
            $message .= Schulferien::Lang::format($L, 'ACTION.APPEND_MQTT', msg => $mqtt_err);
            $msg_type = 'error';
        }
    }
    $tab = 'monitor';

} elsif ($q->request_method eq 'POST' && defined $q->param('restart_daemon')) {
    my $restart_sh = File::Spec->catfile($BIN_DIR, 'restart_daemon.sh');
    if (-x $restart_sh) {
        system("bash $restart_sh $LB_HOME $PLUGIN_FOLDER >/dev/null 2>&1 &");
        $message  = Schulferien::Lang::t($L, 'ACTION.DAEMON_RESTART');
        $msg_type = 'success';
    } else {
        $message  = Schulferien::Lang::t($L, 'ACTION.NO_RESTART');
        $msg_type = 'error';
    }
    $tab = 'monitor';
}

sub _write_state_and_publish {
    my ($cfg, $status, $data_dir, $lb_home, $L) = @_;
    my $state_file = Schulferien::Config::state_store($data_dir);
    if (open my $fh, '>', $state_file) {
        print $fh encode_json($status);
        close $fh;
    }

    my $payload = Schulferien::API::build_mqtt_payload($status);
    my ($mqtt, $info, $conn_err) = Schulferien::LoxBerryMqtt::connect_simple(
        use_loxberry_broker => $cfg->{mqtt_use_loxberry_broker} // 1,
        lb_home             => $lb_home,
        host                => $cfg->{mqtt_host},
        port                => $cfg->{mqtt_port},
        user                => $cfg->{mqtt_user},
        password            => $cfg->{mqtt_password},
    );
    if (!$mqtt) {
        my $addr = $info ? $info->{address} : 'unknown';
        return Schulferien::Lang::format($L, 'ACTION.CONN_FAIL',
            addr  => $addr,
            error => ($conn_err // 'unknown'),
        );
    }

    my $state = Schulferien::Config::normalize_state($cfg->{state});
    my $base  = $cfg->{mqtt_base_topic} // 'loxberry/schulferien';
    my $slug  = $cfg->{mqtt_device_id}  // lc($state);
    my $avail = "$base/$slug/availability";
    my $data  = "$base/$slug/data";

    eval { $mqtt->retain($avail, 'online') };
    return Schulferien::Lang::format($L, 'ACTION.PUBLISH_FAIL', topic => $avail, error => $@) if $@;

    eval { $mqtt->retain($data, encode_json($payload)) };
    return Schulferien::Lang::format($L, 'ACTION.PUBLISH_FAIL', topic => $data, error => $@) if $@;

    return '';
}

# ── Output ────────────────────────────────────────────────────────────────────

print $q->header(-type => 'text/html', -charset => 'utf-8');

print Schulferien::WebUI::render_page(
    L          => $L,
    tab        => $tab,
    cfg        => $cfg,
    base_url   => $SCRIPT_URL,
    plugin_url => $plugin_url,
    message    => $message,
    msg_type   => $msg_type,
    data_dir   => $DATA_DIR,
    log_file   => $LOG_FILE,
);
