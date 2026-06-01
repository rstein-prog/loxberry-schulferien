package Schulferien::Lang;

use strict;
use warnings;
use File::Spec;
use JSON::PP qw(decode_json);

sub load {
    my ($lb_home, $plugin_folder) = @_;
    my $lang = detect_lang($lb_home);

    my %L;
    eval {
        require LoxBerry::Web;
        %L = LoxBerry::Web::readlanguage(undef, 'language.ini');
    };
    if (!%L) {
        my $base = template_lang_dir($lb_home, $plugin_folder);
        my %en = _read_ini(File::Spec->catfile($base, 'language_en.ini'));
        my %user = ($lang ne 'en')
            ? _read_ini(File::Spec->catfile($base, "language_${lang}.ini"))
            : ();
        %L = (%en, %user);
    }

    $L{_lang} = $lang;
    return \%L;
}

sub detect_lang {
    my ($lb_home) = @_;
    my $lang;

    eval {
        require LoxBerry::System;
        $lang = LoxBerry::System::lblanguage();
    };
    $lang //= $ENV{LBPLANG} // $ENV{LBPPLANG} // '';

    if (!$lang && $lb_home) {
        my $path = File::Spec->catfile($lb_home, 'config', 'system', 'general.json');
        if (-f $path && open my $fh, '<', $path) {
            local $/;
            my $raw = eval { decode_json(<$fh>) };
            close $fh;
            if ($raw && ref $raw eq 'HASH') {
                $lang = $raw->{Language} // $raw->{language} // '';
            }
        }
    }

    return 'de' if defined $lang && $lang =~ /^de/i;
    return 'en';
}

sub template_lang_dir {
    my ($lb_home, $plugin_folder) = @_;
    my @candidates;

    if ($ENV{lbptemplatedir}) {
        push @candidates, File::Spec->catdir($ENV{lbptemplatedir}, 'lang');
    }
    if ($lb_home && $plugin_folder) {
        push @candidates, File::Spec->catdir(
            $lb_home, 'templates', 'plugins', $plugin_folder, 'lang'
        );
    }

    for my $dir (@candidates) {
        return $dir if $dir && -d $dir;
    }
    return $candidates[0] // 'lang';
}

sub format {
    my ($L, $key, %vars) = @_;
    my $s = t($L, $key);
    for my $k (keys %vars) {
        my $v = $vars{$k};
        $v = '' if !defined $v;
        $s =~ s/\{$k\}/$v/g;
    }
    return $s;
}

sub t {
    my ($L, $key, $default) = @_;
    $L ||= {};
    return $L->{$key} if defined $L->{$key} && $L->{$key} ne '';
    return $default if defined $default;
    return $key;
}

sub html_lang {
    my ($L) = @_;
    return ($L && ($L->{_lang} // '') eq 'de') ? 'de' : 'en';
}

sub _read_ini {
    my ($path) = @_;
    return () if !$path || !-f $path;

    my (%out, $section);
    open my $fh, '<', $path or return ();
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\x{FEFF}//;
        next if $line =~ /^\s*(?:#|;)/;
        next if $line =~ /^\s*$/;
        if ($line =~ /^\s*\[([^\]]+)\]\s*$/) {
            $section = $1;
            next;
        }
        my ($k, $v) = split(/\s*=\s*/, $line, 2);
        next if !defined $k;
        $v //= '';
        $v =~ s/\s+$//;
        $v =~ s/^"(.*)"$/$1/;
        my $full = defined $section ? "$section.$k" : $k;
        $out{$full} = $v;
    }
    close $fh;
    return %out;
}

1;
