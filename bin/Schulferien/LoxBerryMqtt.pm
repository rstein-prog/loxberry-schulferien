package Schulferien::LoxBerryMqtt;

use strict;
use warnings;

use JSON::PP qw(decode_json);
use File::Spec;

# Resolve LoxBerry MQTT broker settings (host, port, user, password).
# Mirrors the Harvia/Fyta plugins and loxberry-api-abfall-io credential lookup.

sub resolve_broker {
    my (%args) = @_;

    my $lb_home = $args{lb_home} || '/opt/loxberry';
    my $use_loxberry = defined $args{use_loxberry_broker} ? $args{use_loxberry_broker} : 1;

    my $host = _trim($args{host});
    my $port = defined $args{port} && $args{port} =~ /^\d+$/ ? int($args{port}) : 0;
    my $user = defined $args{user} ? $args{user} : '';
    my $password = defined $args{password} ? $args{password} : '';
    my $source = 'manual';

    if ($use_loxberry) {
        my $detected = load_loxberry_broker_credentials($lb_home);
        if ($detected) {
            $host = $detected->{host} if !$host;
            $port = $detected->{port} if !$port;
            $user = $detected->{user} if !length $user;
            $password = $detected->{password} if !length $password;
            $source = $detected->{source};
        }
    }

    $host = 'localhost' if !$host;
    $port = 1883 if !$port;

    return {
        host     => $host,
        port     => $port,
        user     => $user,
        password => $password,
        source   => $source,
        address  => "$host:$port",
    };
}

sub load_loxberry_broker_credentials {
    my ($lb_home) = @_;
    return undef if !$lb_home;

    my $general_json = File::Spec->catfile($lb_home, 'config', 'system', 'general.json');
    if (-f $general_json) {
        my $broker = _read_json_broker($general_json, sub {
            my ($raw) = @_;
            my $mqtt = $raw->{Mqtt} // $raw->{mqtt} // $raw->{MQTT};
            return ref $mqtt eq 'HASH' ? $mqtt : undef;
        });
        return $broker if $broker;
    }

    for my $file (
        File::Spec->catfile($lb_home, 'system', 'storage', 'mqtt', 'cred.json'),
        File::Spec->catfile($lb_home, 'data', 'system', 'storage', 'mqtt', 'cred.json'),
        File::Spec->catfile($lb_home, 'data', 'system', 'mqtt', 'cred.json'),
        File::Spec->catfile($lb_home, 'data', 'plugins', 'mqttgateway', 'cred.json'),
        File::Spec->catfile($lb_home, 'config', 'plugins', 'mqttgateway', 'cred.json'),
        File::Spec->catfile($lb_home, 'config', 'system', 'mqtt.cfg'),
        File::Spec->catfile($lb_home, 'config', 'plugins', 'mqttgateway', 'mqtt.cfg'),
    ) {
        next if !-f $file;
        my $broker = _read_json_broker($file, sub {
            my ($raw) = @_;
            return $raw if ref $raw eq 'HASH';
        });
        if (!$broker) {
            $broker = _read_json_broker($file, sub {
                my ($raw) = @_;
                my $mqtt = $raw->{Mqtt} // $raw->{mqtt};
                return ref $mqtt eq 'HASH' ? $mqtt : undef;
            });
        }
        if (!$broker && $file =~ /\.cfg$/) {
            $broker = _fields_from_hash(_parse_ini_flat($file));
        }
        return $broker if $broker;
    }

    for my $cfg (
        File::Spec->catfile($lb_home, 'config', 'system', 'general.cfg'),
        File::Spec->catfile($lb_home, 'system', 'general.cfg'),
    ) {
        next if !-f $cfg;
        my $section = _parse_ini_section($cfg, 'MQTT') || _parse_ini_section($cfg, 'Mqtt');
        my $broker = _fields_from_hash($section) if $section;
        if ($broker) {
            $broker->{source} = $cfg;
            return $broker;
        }
    }

    return undef;
}

sub _parse_ini_flat {
    my ($path) = @_;
    my %out;
    open my $fh, '<', $path or return undef;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /^[#;]/;
        next if $line =~ /^\[/;
        my ($k, $v) = split(/\s*=\s*/, $line, 2);
        next if !defined $k;
        $v //= '';
        $out{lc $k} = $v;
    }
    close $fh;
    return \%out if keys %out;
    return undef;
}

sub _read_json_broker {
    my ($path, $extract) = @_;

    open my $fh, '<', $path or return undef;
    local $/;
    my $raw = eval { decode_json(<$fh>) };
    close $fh;
    return undef if !$raw;

    my $section = eval { $extract->($raw) };
    return undef if !$section || ref $section ne 'HASH';

    my $broker = _fields_from_hash($section);
    return undef if !$broker;

    $broker->{source} = $path;
    return $broker;
}

sub _fields_from_hash {
    my ($raw) = @_;
    return undef if !$raw || ref $raw ne 'HASH';

    my %lower;
    for my $k (keys %$raw) {
        $lower{lc $k} = $raw->{$k};
    }

    my $host_raw = $lower{brokerhost} // $lower{host} // $lower{brokeraddress};
    return undef if !defined $host_raw || $host_raw eq '';

    my $host = "$host_raw";
    my $port = $lower{brokerport} // $lower{port} // 1883;
    if ($host =~ /^([^:]+):(\d+)$/) {
        $host = $1;
        $port = $2;
    }
    $port = 1883 if !defined $port || $port !~ /^\d+$/;

    return {
        host     => $host,
        port     => int($port),
        user     => defined $lower{brokeruser} ? "$lower{brokeruser}"
            : (defined $lower{user} ? "$lower{user}" : ''),
        password => defined $lower{brokerpass} ? "$lower{brokerpass}"
            : (defined $lower{pass} ? "$lower{pass}"
            : (defined $lower{brokerpassword} ? "$lower{brokerpassword}"
            : (defined $lower{password} ? "$lower{password}" : ''))),
    };
}

sub _parse_ini_section {
    my ($path, $section_name) = @_;

    open my $fh, '<', $path or return undef;
    my $in_section = 0;
    my %out;

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        if ($line =~ /^\[(.+)\]$/) {
            $in_section = lc $1 eq lc $section_name;
            next;
        }
        next if !$in_section || $line eq '' || $line =~ /^[#;]/;
        my ($k, $v) = split(/\s*=\s*/, $line, 2);
        next if !defined $k;
        $v //= '';
        $v =~ s/^"(.*)"$/$1/;
        $out{lc $k} = $v;
    }
    close $fh;

    return \%out if keys %out;
    return undef;
}

sub _trim {
    my ($v) = @_;
    return '' if !defined $v;
    $v =~ s/^\s+|\s+$//g;
    return $v;
}

sub connect_simple {
    my (%args) = @_;

    $ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;
    require Net::MQTT::Simple;

    my $broker = resolve_broker(%args);
    my $mqtt = eval { Net::MQTT::Simple->new($broker->{address}) };
    if (!$mqtt) {
        my $err = $@ || 'connect failed';
        return (undef, $broker, $err);
    }

    if (length $broker->{user}) {
        eval { $mqtt->login($broker->{user}, length $broker->{password} ? $broker->{password} : undef) };
        if ($@) {
            return (undef, $broker, $@);
        }
    }

    return ($mqtt, $broker, '');
}

1;
