#!/usr/bin/env perl 

=head1 NAME
    
    iReadSMSviaSSH

=head1 SYNOPSIS

    iReadSMSviaSSH [OPTIONS] mobile@host
    iReadSMSviaSSH -f sms.db

=head1 OPTIONS

=over

=item help (v)

This message

=item verbose (v)

Verbose mode

=ietm ssh-key (i)

Selects the file from which the identity (private key) for public key authentication is read.
            This option is directly passed to ssh(1)

=item ssh-options (o)

Can be used to pass options to ssh in the format used in ssh_config(5).  This is useful for
            specifying options for which there is no separate scp command-line flag.  For full details of
            the options listed below, and their possible values, see ssh_config(5).

=item file (f)

Use local file database

=item save-read-time (r)

Add read time to after every messase

=item save-service-name (t)

Add service name to after every messase

=item key-checking-no (n)

Not check known_hosts file

=back

=cut



use strict;
use warnings;
use FindBin '$Bin';
use Getopt::Long;
use Pod::Usage;
use DBI;
use Data::Dumper;

my $config = {};

Getopt::Long::Configure ("bundling");
GetOptions(
    "help|h|?"            => sub { usage() },
    "verbose|v+"          => \$config->{verbose},
    "ssh-key|i=s"         => \$config->{'ssh-key'},
    "ssh-port|p=s"        => \$config->{'ssh-port'},
    "ssh-options|o=s"     => \$config->{'ssh-options'},
    "file|f=s"            => \$config->{'file'},
    "save-read-time|t"    => \$config->{'save-read-time'},
    "save-service-name|s" => \$config->{'save-service-name'},
    "key-checking-no|n"   => sub {
        $config->{'ssh-options'} .= ' -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no ';
    },
);

my $ip = shift(@ARGV);

usage() if ! $ip and ! $config->{'file'};

if ($config->{'file'}) {
    read_sms($config->{'file'});
    exit;
}

if ($ip) {
    mkdir "$Bin/var" unless -e "$Bin/var";
    my $options = $config->{'ssh-options'} ||= '';
    my $key = "-i $config->{'ssh-key'}" if $config->{'ssh-key'};
    $key = '' unless $key;
    $options .= "-o Port=$config->{'ssh-port'}" if $config->{'ssh-port'};
    print "Copy $ip:/private/var/mobile/Library/SMS/sms.db to $Bin/var/sms.db" if $config->{verbose};
    system("scp $key $options $ip:/private/var/mobile/Library/SMS/sms.db '$Bin/var/sms.db'");
    read_sms("$Bin/var/sms.db");
}

sub read_sms {
    my ($file) = @_;

    unless (-e "$Bin/sms") {
        mkdir "$Bin/sms" or die "Can't create dir \"$Bin/sms\": $!\n";
    }

    my $db = DBI->connect("dbi:SQLite:$file","","", {RaiseError => 1, AutoCommit => 1});

    my $sth = $db->prepare(qq{
        SELECT 
          m.rowid as RowID, 
          DATETIME(date + 978307200, 'unixepoch', 'localtime') as Date, 
          h.id as "Phone Number", m.service as Service, 
          CASE is_from_me 
            WHEN 0 THEN "Received" 
            WHEN 1 THEN "Sent" 
            ELSE "Unknown" 
          END as Type, 
          CASE 
            WHEN date_read > 0 then DATETIME(date_read + 978307200, 'unixepoch')
            WHEN date_delivered > 0 THEN DATETIME(date_delivered + 978307200, 'unixepoch') 
            ELSE NULL END as "Date Read/Sent", 
          text as Text 
        FROM message m, handle h 
        WHERE h.rowid = m.handle_id 
        ORDER BY m.rowid ASC
    });

    $sth->execute() or die "Can't execute SQL query: $!\n";

    my $h = {};
    my $i = 0;

    while (my $res = $sth->fetchrow_hashref) {
        my $phone_number = $res->{'Phone Number'};
        my $type = '';

        if ($res->{'Type'} eq 'Received') {
            $type = '>';
        } elsif ($res->{'Type'} eq 'Sent') {
            $type = '<';
        } else {
            $type = '-';
        }

        $res->{'Date Read/Sent'} = '' unless $res->{'Date Read/Sent'};

        $i++;

        my $line = '[' . $res->{'Date'} . '] ' . $type . ' ' . $res->{'Text'} . "    ";
        $line .= $res->{'Service'} . ' '  if $config->{'save-service-name'};
        $line .= $res->{'Date Read/Sent'} if $config->{'save-read-time'};

        push @{$h->{ $res->{'Phone Number'} }}, $line;
    }

    $db->disconnect;

    if (! -e "$Bin/sms") {
        mkdir "$Bin/sms" or die "Can't create directory \"$Bin/sms\": $!\n";
    }

    while (my ($phone_number, $sms_array) = each %$h) {
        $phone_number =~ s/^\+//;
        print "Save \"$Bin/sms/$phone_number\"\n" if $config->{'verbose'};
        open my $chat_file, ">", "$Bin/sms/$phone_number" or die
            "Can't create chat file \"$Bin/sms/$phone_number\": $!\n";

        print $chat_file join("\n", @$sms_array);
        close $chat_file;
    }

    print "Total $i SMS\n";
}

sub usage {
    pod2usage(1);
    exit;
}
