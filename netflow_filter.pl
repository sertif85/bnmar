#!/usr/bin/perl -w

use strict;
use warnings;
use feature ':5.10';
use Socket qw/inet_aton/;
use File::Spec::Functions;
use POSIX qw/strftime/;
use Getopt::Long 'HelpMessage';

my ($FILE);
my $DIR = 'netflow_filter_result';
my @NET = ( '147.32.80.0', '255.255.240.0' );

GetOptions(
    'file=s'    => \$FILE,
    'dir=s'     => \$DIR,
    'net=s{,}', => \@NET,
    'help'      => sub { HelpMessage(0) }
) or HelpMessage(1);

my $NET_ADDR = _aton( $NET[0] );
my $NET_MASK = _aton( $NET[1] );

# 0 - Date first seen
# 1 - Time
# 2 - Duration
# 3 - Proto
# 4 - SRC IP Addr:Port
# 5 - Arrow
# 6 - DST IP Addr:Port
# 7 - Flags
# 8 - Tos
# 9 - Packets
# 10 - Bytes
my @COLUMNS_NAME = (qw/date time dur proto src e dst flags tos packets bytes/);

unlink glob catfile( $DIR, '*.txt' );

my ( %BUFFER, $data );
say sprintf( '[%s] Parsing has been started', strftime( "%H:%M:%S", localtime ) );
if ($FILE) {
    open my $fh, '<', $FILE or die $!;

    _loop($_) while <$fh>;

    close $fh;
    undef $fh;
}
else {
    _loop($_) while <>;
}
say sprintf( '[%s] Parsing has been complited', strftime( "%H:%M:%S", localtime ) );
%BUFFER = ();

sub _loop {
    my ($line) = @_;

    return unless $line;

    # If string doesn't contain first 4 digits
    return if $line !~ m/^\d{4}/;

    $data = parse_string($line);

    # Only TCP packets
    return if $data->{'proto'} ne 'TCP';

    calc_data($data);

    if ( $data->{'flags'} =~ m/F/ ) {
        save_data($data);
    }
}

sub parse_string {

    # Split the first and only argument
    my @arr = split /\s+/, $_[0];

    my %hash;
    for ( my $i = 0; $i < @COLUMNS_NAME; ++$i ) {
        $hash{ $COLUMNS_NAME[$i] } = $arr[$i];
    }

    for (qw/src dst/) {
        ( $hash{ $_ . 'ip' }, $hash{ $_ . 'port' } ) = split ':', $hash{$_};
    }

    return \%hash;
}

sub calc_data {
    my ($data) = @_;

    my $addr = _who_from_lan($data);

    return undef unless $addr;

    if ( ref $BUFFER{$addr} eq 'HASH' && %{ $BUFFER{$addr} } ) {

        for (qw/dur packets bytes/) {
            $BUFFER{$addr}->{$_} += $data->{$_};
        }
    }
    else {

        for (qw/dur packets bytes/) {
            $BUFFER{$addr}->{$_} = $data->{$_};
        }

        for (qw/date time proto src dst flags tos/) {
            $BUFFER{$addr}->{$_} = $data->{$_};
        }
    }

    return;
}

sub _aton { unpack( "N", inet_aton( $_[0] ) ) }

sub _is_lan { ( _aton( $_[0] ) & $NET_MASK ) == $NET_ADDR if $_[0]; }

sub _who_from_lan {
    return $_[0]->{'src'} if _is_lan( $_[0]->{'srcip'} );
    return $_[0]->{'dst'} if _is_lan( $_[0]->{'dstip'} );
    return undef;
}

sub save_data {
    my ($data) = @_;

    my $addr = _who_from_lan($data);

    if ($addr) {

        return unless $BUFFER{$addr};

        $data = $BUFFER{$addr};

        unless ( _is_lan( [ split ':', $data->{'src'} ]->[0] ) ) {
            ( $data->{'src'}, $data->{'dst'} ) = ( $data->{'dst'}, $data->{'src'} );
        }

        $data->{'e'} = '->';

        my $file = [ split ':', $addr ]->[0];
        my $filename = catfile( $DIR, "$file.txt" );

        my $format = "%s %s\t%s\t%s %s\t%s\t%s\t%s\t%s\t%s\t%s\n";

        open my $fh, '>>', $filename or die $!;
        print $fh sprintf( $format, @{$data}{@COLUMNS_NAME} );
        close $fh;

        $BUFFER{$addr} = {};
        delete $BUFFER{$addr};
    }
}