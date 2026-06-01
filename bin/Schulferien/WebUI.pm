package Schulferien::WebUI;

use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);
use Schulferien::Config;
use Schulferien::API;

my $PLUGIN_VERSION = '0.2.4';

# ── Helpers ───────────────────────────────────────────────────────────────────

sub _h {
    my ($s) = @_;
    $s //= '';
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

sub _vars {
    my ($cfg) = @_;
    my $state = Schulferien::Config::normalize_state($cfg->{state} // 'BY');
    my $slug  = $cfg->{mqtt_device_id}  // lc($state);
    my $base  = $cfg->{mqtt_base_topic} // 'loxberry/schulferien';
    return (base => $base, slug => $slug);
}

sub _tab_active {
    my ($tab, $current) = @_;
    return ($tab eq ($current // 'config')) ? ' active' : '';
}

# ── Common page chrome ────────────────────────────────────────────────────────

sub _page_head {
    my ($tab, $plugin_url, $L) = @_;
    my $favicon = $plugin_url ? "$plugin_url/icon_64.png" : '';
    my $lang    = Schulferien::Lang::html_lang($L);
    my $title   = _h(Schulferien::Lang::t($L, 'UI.TITLE'));
    return <<HTML;
<!DOCTYPE html>
<html lang="$lang">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title>
@{[ $favicon ? qq{<link rel="icon" type="image/png" href="$favicon">} : '' ]}
<style>
  :root{--accent:#1e40af;--accent-light:#dbeafe;--radius:8px;--shadow:0 2px 8px rgba(0,0,0,.12)}
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:system-ui,sans-serif;font-size:15px;background:#f1f5f9;color:#1e293b;min-height:100vh}
  header{background:var(--accent);color:#fff;padding:14px 20px;display:flex;align-items:center;gap:14px;box-shadow:var(--shadow)}
  header img{height:42px;border-radius:6px}
  header h1{font-size:1.3rem;font-weight:700;letter-spacing:.02em}
  header small{display:block;font-size:.75rem;opacity:.75}
  .back-btn{display:inline-flex;align-items:center;gap:6px;color:#bfdbfe;text-decoration:none;font-size:.85rem;padding:6px 12px;border:1px solid #3b82f680;border-radius:6px;margin-right:4px;transition:.15s;white-space:nowrap}
  .back-btn:hover{background:#1d4ed8;color:#fff;border-color:#60a5fa}
  nav{background:#1e3a8a;display:flex;gap:2px;padding:0 16px}
  nav a{color:#93c5fd;padding:10px 18px;text-decoration:none;font-size:.9rem;border-bottom:3px solid transparent;transition:.15s}
  nav a.active{color:#fff;border-bottom-color:#60a5fa}
  nav a:hover:not(.active){color:#bfdbfe}
  main{max-width:860px;margin:28px auto;padding:0 16px}
  .card{background:#fff;border-radius:var(--radius);box-shadow:var(--shadow);padding:22px;margin-bottom:20px}
  h2{font-size:1.05rem;font-weight:600;color:#1e3a8a;margin-bottom:14px}
  label{display:block;margin-bottom:4px;font-size:.88rem;font-weight:500;color:#374151}
  input,select{width:100%;padding:9px 11px;border:1px solid #cbd5e1;border-radius:6px;font-size:.93rem;background:#fff}
  input:focus,select:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px #bfdbfe80}
  .row{display:grid;grid-template-columns:1fr 1fr;gap:16px}
  \@media(max-width:600px){.row{grid-template-columns:1fr}}
  .form-group{margin-bottom:14px}
  .hint{font-size:.8rem;color:#64748b;margin-top:3px}
  .btn{display:inline-block;padding:10px 20px;border:none;border-radius:6px;font-size:.93rem;font-weight:600;cursor:pointer;transition:.15s}
  .btn-primary{background:var(--accent);color:#fff}
  .btn-primary:hover{background:#1d3faa}
  .btn-secondary{background:#e2e8f0;color:#1e293b}
  .btn-secondary:hover{background:#cbd5e1}
  .btn-success{background:#16a34a;color:#fff}
  .btn-success:hover{background:#15803d}
  .btn-warn{background:#d97706;color:#fff}
  .btn-warn:hover{background:#b45309}
  .alert{padding:12px 16px;border-radius:6px;font-size:.9rem;margin-bottom:16px}
  .alert-success{background:#dcfce7;color:#166534;border-left:4px solid #16a34a}
  .alert-error{background:#fee2e2;color:#991b1b;border-left:4px solid #dc2626}
  .alert-info{background:#dbeafe;color:#1e40af;border-left:4px solid #3b82f6}
  table{width:100%;border-collapse:collapse;font-size:.88rem}
  th{background:#f1f5f9;text-align:left;padding:8px 10px;color:#374151;font-weight:600}
  td{padding:7px 10px;border-bottom:1px solid #f1f5f9}
  tr:last-child td{border-bottom:none}
  .badge{display:inline-block;padding:2px 9px;border-radius:12px;font-size:.78rem;font-weight:700}
  .badge-green{background:#dcfce7;color:#166534}
  .badge-gray{background:#f1f5f9;color:#64748b}
  .badge-blue{background:#dbeafe;color:#1e40af}
  .badge-orange{background:#fef3c7;color:#92400e}
  .badge-purple{background:#ede9fe;color:#5b21b6}
  .is-holiday-banner{background:var(--accent-light);border:1px solid #93c5fd;border-radius:8px;padding:16px 20px;display:flex;align-items:center;gap:14px;margin-bottom:18px}
  .is-holiday-banner .icon{font-size:2.2rem}
  .is-holiday-banner strong{font-size:1.1rem;color:#1e40af}
  details.acc{border-radius:var(--radius);box-shadow:var(--shadow);background:#fff;overflow:hidden;margin-bottom:20px}
  details.acc summary{padding:16px 20px;cursor:pointer;font-weight:600;color:#1e3a8a;list-style:none;display:flex;align-items:center;gap:10px;user-select:none}
  details.acc summary::-webkit-details-marker{display:none}
  details.acc summary::after{content:'\25BC';font-size:.75rem;margin-left:auto;transition:.2s;color:#94a3b8}
  details.acc[open] summary::after{transform:rotate(180deg)}
  details.acc summary .acc-hint{font-size:.8rem;font-weight:400;color:#94a3b8}
  .acc-body{padding:0 20px 20px;border-top:1px solid #f1f5f9}
  .acc-body ol,.acc-body ul{padding-left:20px;margin:10px 0}
  .acc-body li{margin-bottom:6px;line-height:1.5}
  .acc-body p{margin:8px 0;line-height:1.55}
  .acc-body table{margin:10px 0}
  .acc-body code,.acc-body pre{background:#f1f5f9;border-radius:4px;font-family:monospace;font-size:.87em}
  .acc-body code{padding:1px 5px}
  .acc-body pre{padding:10px 14px;overflow-x:auto;line-height:1.5;white-space:pre-wrap;word-break:break-all}
  pre.log{background:#0f172a;color:#e2e8f0;border-radius:6px;padding:14px;font-size:.82rem;line-height:1.4;max-height:300px;overflow-y:auto;font-family:monospace;white-space:pre-wrap;word-break:break-all}
</style>
</head>
<body>
HTML
}

sub _page_header {
    my ($plugin_url, $L) = @_;
    my $logo = $plugin_url ? qq{<img src="$plugin_url/icon_64.png" alt="Schulferien">} : '';
    my $page_title = _h(Schulferien::Lang::t($L, 'UI.PAGE_TITLE'));
    my $subtitle   = Schulferien::Lang::format($L, 'UI.SUBTITLE', version => $PLUGIN_VERSION);
    return <<HTML;
<header>
  <a href="/admin/index.cgi" class="back-btn">&#x2190; @{[_h(Schulferien::Lang::t($L, 'UI.BACK'))]}</a>
  $logo
  <div><h1>$page_title</h1><small>$subtitle</small></div>
</header>
HTML
}

sub _page_nav {
    my ($tab, $base_url, $L) = @_;
    my $tabs = [
        ['config',  '&#x2699;&#xFE0F; ' . Schulferien::Lang::t($L, 'UI.TAB_CONFIG')],
        ['monitor', '&#x1F4CA; ' . Schulferien::Lang::t($L, 'UI.TAB_MONITOR')],
    ];
    my $html = "<nav>\n";
    for my $t (@$tabs) {
        my $cls = _tab_active($t->[0], $tab);
        $html .= qq{  <a href="${base_url}?tab=$t->[0]" class="$cls">$t->[1]</a>\n};
    }
    $html .= "</nav>\n";
    return $html;
}

sub _acc_first {
    my ($L, $cfg) = @_;
    my %v = _vars($cfg);
    my $lox = Schulferien::Lang::format($L, 'ACC_FIRST.LOXONE_EXAMPLE', %v);
    return <<HTML;
<details class="acc">
  <summary>&#x1F680; @{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.SUMMARY'))]} <span class="acc-hint">@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.HINT'))]}</span></summary>
  <div class="acc-body">
    <ol>
      <li>@{[Schulferien::Lang::t($L, 'ACC_FIRST.STEP1')]}</li>
      <li>@{[Schulferien::Lang::t($L, 'ACC_FIRST.STEP2')]}</li>
      <li>@{[Schulferien::Lang::t($L, 'ACC_FIRST.STEP3')]}</li>
      <li>@{[Schulferien::Lang::t($L, 'ACC_FIRST.STEP4')]}</li>
      <li>@{[Schulferien::Lang::t($L, 'ACC_FIRST.STEP5')]}</li>
    </ol>
    <p><strong>@{[Schulferien::Lang::format($L, 'ACC_FIRST.TOPICS_TITLE', %v)]}</strong></p>
    <table>
      <tr><th>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.TH_TOPIC'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.TH_PAYLOAD'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.TH_DIR'))]}</th></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::format($L, 'ACC_FIRST.TOPIC_DATA', %v))]}</code></td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.PAYLOAD_COMPACT'))]}</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.DIR_PUB'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::format($L, 'ACC_FIRST.TOPIC_AVAIL', %v))]}</code></td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.PAYLOAD_AVAIL'))]}</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.DIR_PUB'))]}</td></tr>
    </table>
    <p><strong>@{[Schulferien::Lang::t($L, 'ACC_FIRST.JSON_TITLE')]}</strong></p>
    <table>
      <tr><th>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.TH_PATH'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.TH_TYPE'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.TH_DESC'))]}</th></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_STATE'))]}</code></td><td>Text</td><td>@{[Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_STATE_DESC')]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_ACTIVE'))]}</code></td><td>0 / 1</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_ACTIVE_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_NAME'))]}</code></td><td>Text</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_NAME_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_DATES'))]}</code></td><td>YYYY-MM-DD</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_DATES_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_LEFT'))]}</code></td><td>Number</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_LEFT_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_SCHOOL'))]}</code></td><td>Object</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_SCHOOL_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_PUBLIC'))]}</code></td><td>Object</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_NOW_PUBLIC_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_NAME'))]}</code></td><td>Text</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_NAME_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_DATES'))]}</code></td><td>YYYY-MM-DD</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_DATES_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_IN'))]}</code></td><td>Number</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_IN_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_LEN'))]}</code></td><td>Number</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_LEN_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_SCHOOL'))]}</code></td><td>Object</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_SCHOOL_DESC'))]}</td></tr>
      <tr><td><code>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_PUBLIC'))]}</code></td><td>Object</td><td>@{[_h(Schulferien::Lang::t($L, 'ACC_FIRST.FIELD_SOON_PUBLIC_DESC'))]}</td></tr>
    </table>
    <p><strong>@{[Schulferien::Lang::format($L, 'ACC_FIRST.LOXONE_TITLE', %v)]}</strong></p>
    <pre>$lox</pre>
    <p>@{[Schulferien::Lang::t($L, 'ACC_FIRST.LOXONE_NOTE')]}</p>
    <p>@{[Schulferien::Lang::t($L, 'ACC_FIRST.API_NOTE')]}</p>
  </div>
</details>

<details class="acc">
  <summary>&#x2696;&#xFE0F; @{[_h(Schulferien::Lang::t($L, 'ACC_LEGAL.SUMMARY'))]}</summary>
  <div class="acc-body">
    <p>@{[Schulferien::Lang::t($L, 'ACC_LEGAL.P1')]}</p>
    <p>@{[Schulferien::Lang::t($L, 'ACC_LEGAL.P2')]}</p>
    <p>@{[Schulferien::Lang::t($L, 'ACC_LEGAL.P3')]}</p>
    <p>@{[Schulferien::Lang::t($L, 'ACC_LEGAL.P4')]}</p>
  </div>
</details>
HTML
}

# ── Config tab ────────────────────────────────────────────────────────────────

sub render_config_tab {
    my (%args) = @_;
    my $L       = $args{L}        or die 'L required';
    my $cfg     = $args{cfg}       or die 'cfg required';
    my $message = $args{message}   // '';
    my $msg_type = $args{msg_type} // 'info';
    my $base    = $args{base_url}  // '';
    my $purl    = $args{plugin_url} // '';

    my $alert = $message
        ? qq{<div class="alert alert-$msg_type">$message</div>}
        : '';

    my @state_codes = sort keys %Schulferien::Config::STATES;
    my $state_opts = join "\n", map {
        my $sel = (uc($cfg->{state} // '') eq $_) ? ' selected' : '';
        qq{<option value="$_"$sel>$_ – $Schulferien::Config::STATES{$_}</option>}
    } @state_codes;

    my $use_lb_checked = ($cfg->{mqtt_use_loxberry_broker} // 1) ? ' checked' : '';
    my $enabled_checked = ($cfg->{enabled} // 1) ? ' checked' : '';

    my $interval_hours = int(($cfg->{poll_interval} // 21600) / 3600);
    $interval_hours = 6 if $interval_hours < 6;
    my $interval_h   = _h($interval_hours);
    my $host     = _h($cfg->{mqtt_host}     // '');
    my $port     = _h($cfg->{mqtt_port}     // 1883);
    my $user     = _h($cfg->{mqtt_user}     // '');
    my $pass     = _h($cfg->{mqtt_password} // '');
    my $base_topic = _h($cfg->{mqtt_base_topic} // 'loxberry/schulferien');
    my $device_id  = _h($cfg->{mqtt_device_id}  // 'by');

    return <<HTML;
<div class="card">
  $alert
  <h2>@{[_h(Schulferien::Lang::t($L, 'CFG.CONFIG_TITLE'))]}</h2>
  <form method="post" action="${base}">
    <input type="hidden" name="tab" value="config">
    <div class="form-group">
      <label>@{[_h(Schulferien::Lang::t($L, 'CFG.STATE'))]}</label>
      <select name="state" onchange="this.form.mqtt_device_id.value=this.value.toLowerCase()">
        $state_opts
      </select>
      <div class="hint">@{[_h(Schulferien::Lang::t($L, 'CFG.STATE_HINT'))]}</div>
    </div>
    <div class="form-group">
      <label><input type="checkbox" name="enabled" value="1"$enabled_checked> @{[_h(Schulferien::Lang::t($L, 'CFG.ENABLED'))]}</label>
    </div>
    <div class="form-group">
      <label>@{[_h(Schulferien::Lang::t($L, 'CFG.POLL_INTERVAL'))]}</label>
      <input type="number" name="poll_interval_hours" value="$interval_h" min="6" max="168" step="1">
      <div class="hint">@{[_h(Schulferien::Lang::t($L, 'CFG.POLL_HINT'))]}</div>
    </div>
    <h2 style="margin-top:16px">@{[_h(Schulferien::Lang::t($L, 'CFG.MQTT_TITLE'))]}</h2>
    <div class="form-group">
      <label><input type="checkbox" name="mqtt_use_loxberry_broker" value="1"$use_lb_checked> @{[_h(Schulferien::Lang::t($L, 'CFG.USE_LB'))]}</label>
      <div class="hint">@{[_h(Schulferien::Lang::t($L, 'CFG.USE_LB_HINT'))]}</div>
    </div>
    <div class="row">
      <div class="form-group">
        <label>@{[_h(Schulferien::Lang::t($L, 'CFG.BASE_TOPIC'))]}</label>
        <input type="text" name="mqtt_base_topic" value="$base_topic">
      </div>
      <div class="form-group">
        <label>@{[_h(Schulferien::Lang::t($L, 'CFG.DEVICE_SLUG'))]}</label>
        <input type="text" name="mqtt_device_id" id="mqtt_device_id" value="$device_id">
        <div class="hint">@{[Schulferien::Lang::t($L, 'CFG.DEVICE_SLUG_HINT')]}</div>
      </div>
    </div>
    <div class="row">
      <div class="form-group">
        <label>@{[_h(Schulferien::Lang::t($L, 'CFG.MQTT_HOST'))]}</label>
        <input type="text" name="mqtt_host" value="$host" placeholder="127.0.0.1">
      </div>
      <div class="form-group">
        <label>@{[_h(Schulferien::Lang::t($L, 'CFG.MQTT_PORT'))]}</label>
        <input type="number" name="mqtt_port" value="$port" min="1" max="65535">
      </div>
    </div>
    <div class="row">
      <div class="form-group">
        <label>@{[_h(Schulferien::Lang::t($L, 'CFG.MQTT_USER'))]}</label>
        <input type="text" name="mqtt_user" value="$user" autocomplete="off">
      </div>
      <div class="form-group">
        <label>@{[_h(Schulferien::Lang::t($L, 'CFG.MQTT_PASS'))]}</label>
        <input type="password" name="mqtt_password" value="$pass" autocomplete="off">
      </div>
    </div>
    <div style="margin-top:6px">
      <button type="submit" name="save_config" value="1" class="btn btn-primary">&#x1F4BE; @{[_h(Schulferien::Lang::t($L, 'CFG.SAVE'))]}</button>
    </div>
  </form>
</div>

@{[_acc_first($L, $cfg)]}
HTML
}

# ── Monitor tab ───────────────────────────────────────────────────────────────

sub _read_status_cache {
    my ($data_dir) = @_;
    my $state_file = Schulferien::Config::state_store($data_dir);
    return undef if !-f $state_file;

    open my $fh, '<', $state_file or return undef;
    local $/;
    my $raw = <$fh>;
    close $fh;

    my $status = eval { decode_json($raw) };
    return undef if $@ || ref $status ne 'HASH';
    return $status;
}

sub _status_cache_stale {
    my ($status, $state) = @_;
    return 1 if !$status || ref $status ne 'HASH';
    return 1 if ($status->{cache_version} // 0) < 2;
    return 1 if Schulferien::Config::normalize_state($status->{state} // '') ne $state;
    return 1 if !exists $status->{is_public_holiday};
    return 1 if !exists $status->{public_holidays};
    my @public_in_list = grep { ($_->{kind} // '') eq 'public' } @{ $status->{holidays} // [] };
    return 1 if !@public_in_list && @{ $status->{public_holidays} // [] };
    return 0;
}

sub _load_monitor_status {
    my ($cfg, $data_dir) = @_;
    my $state  = Schulferien::Config::normalize_state($cfg->{state});
    my $status = _read_status_cache($data_dir);

    if ($status && !_status_cache_stale($status, $state)) {
        return ($status, '');
    }

    my ($fresh, $err);
    eval { ($fresh, $err) = Schulferien::API::build_status_for_state($state); 1 }
        or $err = $@ || 'API error';

    if ($fresh && ref $fresh eq 'HASH') {
        my $path = Schulferien::Config::state_store($data_dir);
        if (open my $fh, '>', $path) {
            print $fh encode_json($fresh);
            close $fh;
        }
        return ($fresh, $err // '');
    }

    return ($status, $err // '') if $status;
    return (undef, $err // '');
}

sub render_monitor_tab {
    my (%args) = @_;
    my $L        = $args{L}        or die 'L required';
    my $cfg      = $args{cfg}      or die 'cfg required';
    my $base     = $args{base_url} // '';
    my $data_dir = $args{data_dir} // '';

    my $state      = Schulferien::Config::normalize_state($cfg->{state});
    my $state_name = Schulferien::Config::state_label($state);
    my $base_topic = $cfg->{mqtt_base_topic} // 'loxberry/schulferien';
    my $slug       = $cfg->{mqtt_device_id}  // lc($state);
    my $data_topic = "$base_topic/$slug/data";

    my $status_html = '';
    my $holidays_html = '';
    my ($status, $status_load_err) = _load_monitor_status($cfg, $data_dir);
    if ($status) {
            my $is_hol = $status->{is_holiday} // 0;
            if ($is_hol) {
                my $left = $status->{holiday_days_left} // 0;
                my $end_d = Schulferien::API::iso_to_display($status->{holiday_end} // '');
                my $hol_title = Schulferien::Lang::format($L, 'MON.HOLIDAY_TODAY',
                    name       => _h($status->{holiday_name} // ''),
                    state_name => _h($state_name),
                );
                my $days_left = '';
                if ($status->{is_school_holiday}) {
                    $days_left = Schulferien::Lang::format($L, 'MON.DAYS_LEFT',
                        left => $left,
                        end  => _h($end_d),
                    );
                } elsif ($status->{is_public_holiday}) {
                    $days_left = Schulferien::Lang::t($L, 'MON.PUBLIC_TODAY');
                }
                $status_html = <<HTML;
<div class="is-holiday-banner">
  <span class="icon">&#x1F3D6;&#xFE0F;</span>
  <div>
    $hol_title
    @{[ $days_left ? "<br>$days_left" : '' ]}
  </div>
</div>
HTML
            } else {
                my $next = _h($status->{next_name} // '');
                my $ndays = $status->{next_days} // '?';
                my $nstart = Schulferien::API::iso_to_display($status->{next_start} // '');
                my $next_line = $next
                    ? Schulferien::Lang::format($L, 'MON.NEXT_HOLIDAY',
                        next  => $next,
                        days  => $ndays,
                        start => _h($nstart),
                    )
                    : '';
                $status_html = <<HTML;
<div class="alert alert-info">
  &#x1F4DA; @{[_h(Schulferien::Lang::format($L, 'MON.NO_HOLIDAY', state_name => $state_name))]}
  @{[ $next_line ? " $next_line" : '' ]}
</div>
HTML
            }

            my @hols = @{$status->{holidays} // []};
            if (@hols) {
                my $today = Schulferien::API::today_iso();
                my $rows = '';
                for my $h (@hols) {
                    my $start = Schulferien::API::iso_to_display($h->{start} // '');
                    my $end   = Schulferien::API::iso_to_display($h->{end}   // '');
                    my ($badge, $label);
                    if (($h->{end} // '') lt $today) {
                        $badge = 'badge-gray';
                        $label = Schulferien::Lang::t($L, 'MON.BADGE_PAST');
                    } elsif (($h->{start} // '') le $today && ($h->{end} // '') ge $today) {
                        $badge = 'badge-green';
                        $label = Schulferien::Lang::t($L, 'MON.BADGE_NOW');
                    } else {
                        $badge = 'badge-blue';
                        $label = Schulferien::Lang::t($L, 'MON.BADGE_PLANNED');
                    }
                    my $kind = ($h->{kind} // 'school') eq 'public'
                        ? Schulferien::Lang::t($L, 'MON.TYPE_PUBLIC')
                        : Schulferien::Lang::t($L, 'MON.TYPE_SCHOOL');
                    my $kind_badge = ($h->{kind} // 'school') eq 'public' ? 'badge-purple' : 'badge-orange';
                    $rows .= <<HTML;
<tr>
  <td>${\( _h($h->{name} // '') )}</td>
  <td><span class="badge $kind_badge">@{[_h($kind)]}</span></td>
  <td>${\( _h($start) )}</td>
  <td>${\( _h($end) )}</td>
  <td><span class="badge $badge">@{[_h($label)]}</span></td>
</tr>
HTML
                }
                $holidays_html = <<HTML;
<h2>@{[_h(Schulferien::Lang::format($L, 'MON.HOLIDAYS_TITLE', state_name => $state_name))]}</h2>
<table>
  <tr><th>@{[_h(Schulferien::Lang::t($L, 'MON.TH_NAME'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'MON.TH_TYPE'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'MON.TH_FROM'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'MON.TH_TO'))]}</th><th>@{[_h(Schulferien::Lang::t($L, 'MON.TH_STATUS'))]}</th></tr>
  $rows
</table>
HTML
            }
    }

    my $no_cache_note = '';
    if (!$status_html) {
        if ($status_load_err) {
            $no_cache_note = <<HTML;
<div class="alert alert-error">@{[_h(Schulferien::Lang::format($L, 'ACTION.API_ERROR', error => $status_load_err))]}</div>
HTML
        } else {
            $no_cache_note = <<HTML;
<div class="alert alert-info">@{[_h(Schulferien::Lang::format($L, 'MON.NO_CACHE', state_name => $state_name))]}</div>
HTML
        }
    }

    my $log_html = '';
    my $log_file = $args{log_file} // '';
    if ($log_file && -f $log_file) {
        my @lines;
        if (open my $lfh, '<', $log_file) {
            @lines = <$lfh>;
            close $lfh;
        }
        my @tail = @lines > 60 ? @lines[-60 .. -1] : @lines;
        my $tail = _h(join '', @tail);
        $log_html = <<HTML;
<h2 style="margin-top:18px">@{[_h(Schulferien::Lang::t($L, 'MON.LOG_TITLE'))]}</h2>
<pre class="log">$tail</pre>
HTML
    }

    my $status_heading = Schulferien::Lang::format($L, 'MON.STATUS_TITLE',
        state_name => $state_name,
        state      => $state,
    );

    return <<HTML;
<div class="card">
  <h2>$status_heading</h2>
  <p class="hint" style="margin-bottom:12px">@{[_h(Schulferien::Lang::t($L, 'MON.MQTT_TOPIC_HINT'))]} <code>${\( _h($data_topic) )}</code></p>
  $no_cache_note
  $status_html
  $holidays_html
  $log_html

  <div style="margin-top:18px;display:flex;gap:10px;flex-wrap:wrap">
    <form method="post" action="${base}" style="display:inline">
      <input type="hidden" name="tab" value="monitor">
      <button type="submit" name="refresh_now" value="1" class="btn btn-success">&#x21BB; @{[_h(Schulferien::Lang::t($L, 'MON.BTN_REFRESH'))]}</button>
    </form>
    <form method="post" action="${base}" style="display:inline">
      <input type="hidden" name="tab" value="monitor">
      <button type="submit" name="restart_daemon" value="1" class="btn btn-warn">&#x1F504; @{[_h(Schulferien::Lang::t($L, 'MON.BTN_RESTART'))]}</button>
    </form>
    <a href="${base}?tab=monitor" class="btn btn-secondary">&#x1F504; @{[_h(Schulferien::Lang::t($L, 'MON.BTN_RELOAD'))]}</a>
  </div>
</div>
HTML
}

# ── Page assembly ─────────────────────────────────────────────────────────────

sub render_page {
    my (%args) = @_;
    my $L     = $args{L}     or die 'L required';
    my $tab     = $args{tab}     // 'config';
    my $base    = $args{base_url} // '';
    my $purl    = $args{plugin_url} // '';

    my $head   = _page_head($tab, $purl, $L);
    my $header = _page_header($purl, $L);
    my $nav    = _page_nav($tab, $base, $L);

    my $content;
    if ($tab eq 'monitor') {
        $content = render_monitor_tab(%args);
    } else {
        $content = render_config_tab(%args);
    }

    return $head . $header . $nav . "<main>$content</main></body></html>\n";
}

1;
