package Schulferien::API;

use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use POSIX qw(floor);

our $BASE_URL           = 'https://schulferien-api.de';
our $FEiertage_BASE_URL = 'https://feiertage-api.de';

# ── Date helpers ─────────────────────────────────────────────────────────────

sub today_iso {
    my @t = localtime(time());
    return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

sub _jdn {
    my ($iso) = @_;
    my ($y, $m, $d) = $iso =~ /^(\d{4})-(\d{2})-(\d{2})/;
    return 0 unless $y;
    my $a = int((14 - $m) / 12);
    my $yy = $y + 4800 - $a;
    my $mm = $m + 12 * $a - 3;
    return $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4)
           - int($yy / 100) + int($yy / 400) - 32045;
}

sub days_between {
    my ($from_iso, $to_iso) = @_;
    return _jdn($to_iso) - _jdn($from_iso);
}

sub iso_to_display {
    my ($iso) = @_;
    return '' unless defined $iso && $iso =~ /^(\d{4})-(\d{2})-(\d{2})/;
    return "$3.$2.$1";
}

sub _strip_time {
    my ($ts) = @_;
    return '' unless defined $ts;
    $ts =~ s/T.*//;
    return $ts;
}

sub _normalize_state {
    my ($code) = @_;
    require Schulferien::Config;
    return Schulferien::Config::normalize_state($code);
}

sub _holiday_state {
    my ($h) = @_;
    return uc($h->{state} // $h->{stateCode} // '');
}

sub filter_holidays_for_state {
    my ($holidays, $state) = @_;
    $state = _normalize_state($state);
    return [ grep { _holiday_state($_) eq $state } @$holidays ];
}

# ── HTTP fetch ────────────────────────────────────────────────────────────────

sub _fetch_url {
    my ($url) = @_;
    eval { require LWP::UserAgent } or return (undef, 'LWP::UserAgent not available');
    my $ua = LWP::UserAgent->new(timeout => 15, agent => 'LoxBerry-Schulferien/0.2');
    my $resp = $ua->get($url);
    if ($resp->is_success) {
        return ($resp->decoded_content, undef);
    }
    return (undef, 'HTTP ' . $resp->status_line);
}

sub fetch_holidays {
    my (%args) = @_;
    my $state = _normalize_state($args{state});
    my $year  = $args{year} // (localtime(time()))[5] + 1900;

    my $url = "$BASE_URL/api/v1/$year/$state";
    my ($body, $err) = _fetch_url($url);
    return ([], $err) if $err;

    my $data = eval { decode_json($body) };
    return ([], "JSON parse error: $@") if $@;
    return ([], 'unexpected response format') if ref $data ne 'ARRAY';

    my @holidays;
    for my $h (@$data) {
        next if ref $h ne 'HASH';
        my $entry_state = _normalize_state($h->{stateCode} // $state);
        next unless $entry_state eq $state;

        my $start = _strip_time($h->{start});
        my $end   = _strip_time($h->{end});
        next unless $start && $end;
        push @holidays, {
            name  => $h->{name_cp} // $h->{name} // 'Ferien',
            slug  => $h->{slug} // $h->{name} // '',
            start => $start,
            end   => $end,
            year  => $h->{year} // $year,
            state => $entry_state,
            kind  => 'school',
        };
    }
    return (\@holidays, undef);
}

sub fetch_holidays_multi_year {
    my (%args) = @_;
    my $state = _normalize_state($args{state});
    my $this_year = (localtime(time()))[5] + 1900;

    my @all;
    my %seen;
    my $last_err;
    for my $yr ($this_year, $this_year + 1) {
        my ($list, $err) = fetch_holidays(state => $state, year => $yr);
        if ($err) { $last_err = $err; next; }
        for my $h (@$list) {
            my $key = join '|', $h->{kind}, $h->{state}, $h->{slug}, $h->{start}, $h->{end};
            next if $seen{$key}++;
            push @all, $h;
        }
    }
    return (\@all, scalar @all ? undef : ($last_err // 'no data'));
}

sub fetch_public_holidays {
    my (%args) = @_;
    my $state = _normalize_state($args{state});
    my $year  = $args{year} // (localtime(time()))[5] + 1900;

    my $url = "$FEiertage_BASE_URL/api/?jahr=$year&nur_land=$state";
    my ($body, $err) = _fetch_url($url);
    return ([], $err) if $err;

    my $data = eval { decode_json($body) };
    return ([], "JSON parse error: $@") if $@;
    return ([], 'unexpected feiertage response') if ref $data ne 'HASH';

    my @holidays;
    for my $name (sort keys %$data) {
        my $entry = $data->{$name};
        next if ref $entry ne 'HASH';
        my $datum = $entry->{datum} // '';
        next unless $datum =~ /^\d{4}-\d{2}-\d{2}$/;
        push @holidays, {
            name  => $name,
            slug  => $name,
            start => $datum,
            end   => $datum,
            year  => $year,
            state => $state,
            kind  => 'public',
        };
    }
    return (\@holidays, undef);
}

sub fetch_public_holidays_multi_year {
    my (%args) = @_;
    my $state = _normalize_state($args{state});
    my $this_year = (localtime(time()))[5] + 1900;

    my @all;
    my %seen;
    my $last_err;
    for my $yr ($this_year, $this_year + 1) {
        my ($list, $err) = fetch_public_holidays(state => $state, year => $yr);
        if ($err) { $last_err = $err; next; }
        for my $h (@$list) {
            my $key = join '|', $h->{kind}, $h->{state}, $h->{name}, $h->{start};
            next if $seen{$key}++;
            push @all, $h;
        }
    }
    return (\@all, scalar @all ? undef : ($last_err // 'no public holiday data'));
}

sub _merge_school_ranges {
    my ($school) = @_;
    my @sorted = sort { $a->{start} cmp $b->{start} } @$school;
    my @merged;
    for my $h (@sorted) {
        if (@merged
            && $merged[-1]{name} eq $h->{name}
            && $merged[-1]{state} eq $h->{state}
            && $merged[-1]{year} == $h->{year}
            && days_between($merged[-1]{end}, $h->{start}) <= 1)
        {
            $merged[-1]{end} = $h->{end} if $h->{end} gt $merged[-1]{end};
        } else {
            push @merged, { %$h };
        }
    }
    return @merged;
}

sub _find_current {
    my ($events, $today) = @_;
    for my $h (@$events) {
        return $h if $h->{start} le $today && $h->{end} ge $today;
    }
    return undef;
}

sub _find_next {
    my ($events, $today) = @_;
    for my $h (@$events) {
        return $h if $h->{start} gt $today;
    }
    return undef;
}

sub _event_metrics {
    my ($h, $today) = @_;
    return {} if !$h;
    my $left = days_between($today, $h->{end});
    my $in   = days_between($today, $h->{start});
    my $len  = days_between($h->{start}, $h->{end}) + 1;
    return {
        name  => $h->{name}  // '',
        start => $h->{start} // '',
        end   => $h->{end}   // '',
        left  => 0 + $left,
        in    => 0 + $in,
        len   => 0 + $len,
    };
}

sub build_status_for_state {
    my ($state) = @_;
    $state = _normalize_state($state);

    my ($school, $err_s) = fetch_holidays_multi_year(state => $state);
    my ($public, $err_p) = fetch_public_holidays_multi_year(state => $state);

    my @errors;
    push @errors, "schulferien: $err_s" if $err_s;
    push @errors, "feiertage: $err_p"   if $err_p;

    if (!@$school && !@$public) {
        return (undef, join('; ', @errors) || 'no data');
    }

    my $status = compute_status($school, $public, undef, $state);
    my $err = @errors ? join('; ', @errors) : undef;
    return ($status, $err);
}

# ── Status computation ────────────────────────────────────────────────────────

sub compute_status {
    my ($school_holidays, $public_holidays, $today, $state) = @_;
    $today //= today_iso();
    $state = _normalize_state($state) if defined $state;

    $school_holidays //= [];
    $public_holidays //= [];

    my @school = _merge_school_ranges(
        [ grep { ($_->{kind} // 'school') eq 'school' } @$school_holidays ]
    );
    my @public = sort { $a->{start} cmp $b->{start} }
        grep { ($_->{kind} // '') eq 'public' } @$public_holidays;

    my $school_now = _find_current(\@school, $today);
    my $public_now = _find_current(\@public, $today);
    my $school_next = _find_next(\@school, $today);
    my $public_next = _find_next(\@public, $today);

    my $school_m = _event_metrics($school_now, $today);
    my $public_m = _event_metrics($public_now, $today);
    my $school_soon = _event_metrics($school_next, $today);
    my $public_soon = _event_metrics($public_next, $today);

    my $is_school = $school_now ? 1 : 0;
    my $is_public = $public_now ? 1 : 0;
    my $is_free   = ($is_school || $is_public) ? 1 : 0;

    my @names;
    push @names, $school_m->{name} if $is_school && $school_m->{name} ne '';
    push @names, $public_m->{name} if $is_public && $public_m->{name} ne '';
    my $combined_name = join(' + ', @names);

    my ($holiday_start, $holiday_end, $holiday_days_left);
    if ($school_now) {
        $holiday_start     = $school_m->{start};
        $holiday_end       = $school_m->{end};
        $holiday_days_left = $school_m->{left};
    } elsif ($public_now) {
        $holiday_start     = $public_m->{start};
        $holiday_end       = $public_m->{end};
        $holiday_days_left = 0;
    }

    my ($next_name, $next_start, $next_end, $next_days, $next_duration);
    my @candidates = grep { $_ } ($school_next, $public_next);
    if (@candidates) {
        my $first = (sort { $a->{start} cmp $b->{start} } @candidates)[0];
        my $m = _event_metrics($first, $today);
        $next_name     = $m->{name};
        $next_start    = $m->{start};
        $next_end      = $m->{end};
        $next_days     = $m->{in};
        $next_duration = $m->{len};
    }

    my @all_display = sort { $a->{start} cmp $b->{start} || ($a->{kind} cmp $b->{kind}) }
        (@school, @public);

    return {
        cache_version       => 2,
        state               => $state // ($school[0]{state} // $public[0]{state} // ''),
        is_holiday          => $is_free,
        is_school_holiday   => $is_school,
        is_public_holiday   => $is_public,
        holiday_name        => $combined_name,
        school_holiday_name => $school_m->{name} // '',
        public_holiday_name => $public_m->{name} // '',
        holiday_start         => $holiday_start // '',
        holiday_end           => $holiday_end   // '',
        holiday_days_left     => 0 + ($holiday_days_left // 0),
        school_holiday_start  => $school_m->{start} // '',
        school_holiday_end    => $school_m->{end}   // '',
        public_holiday_date   => $public_m->{start} // '',
        next_name           => $next_name     // '',
        next_start          => $next_start    // '',
        next_end            => $next_end      // '',
        next_days           => 0 + ($next_days // 0),
        next_duration       => 0 + ($next_duration // 0),
        next_school_name    => $school_soon->{name}  // '',
        next_school_start   => $school_soon->{start} // '',
        next_school_end     => $school_soon->{end}   // '',
        next_school_days    => 0 + ($school_soon->{in}  // 0),
        next_school_len     => 0 + ($school_soon->{len} // 0),
        next_public_name    => $public_soon->{name}  // '',
        next_public_start   => $public_soon->{start} // '',
        next_public_days    => 0 + ($public_soon->{in} // 0),
        as_of               => $today,
        holidays            => \@all_display,
        school_holidays     => \@school,
        public_holidays     => \@public,
    };
}

sub build_mqtt_payload {
    my ($status) = @_;
    my $school_left = 0;
    if ($status->{is_school_holiday}) {
        $school_left = 0 + ($status->{holiday_days_left} // 0);
    }

    return {
        state => $status->{state} // '',
        now   => {
            active => 0 + ($status->{is_holiday}        // 0),
            name   => $status->{holiday_name}            // '',
            start  => $status->{holiday_start}           // '',
            end    => $status->{holiday_end}             // '',
            left   => 0 + ($status->{holiday_days_left}  // 0),
            school => {
                active => 0 + ($status->{is_school_holiday}   // 0),
                name   => $status->{school_holiday_name}     // '',
                start  => $status->{school_holiday_start}    // '',
                end    => $status->{school_holiday_end}      // '',
                left   => $school_left,
            },
            public => {
                active => 0 + ($status->{is_public_holiday}   // 0),
                name   => $status->{public_holiday_name}     // '',
                date   => $status->{public_holiday_date}     // '',
            },
        },
        soon  => {
            name  => $status->{next_name}     // '',
            start => $status->{next_start}    // '',
            end   => $status->{next_end}      // '',
            in    => 0 + ($status->{next_days}     // 0),
            len   => 0 + ($status->{next_duration} // 0),
            school => {
                name  => $status->{next_school_name}  // '',
                start => $status->{next_school_start} // '',
                end   => $status->{next_school_end}   // '',
                in    => 0 + ($status->{next_school_days} // 0),
                len   => 0 + ($status->{next_school_len}  // 0),
            },
            public => {
                name  => $status->{next_public_name}  // '',
                start => $status->{next_public_start} // '',
                in    => 0 + ($status->{next_public_days} // 0),
            },
        },
    };
}

1;
