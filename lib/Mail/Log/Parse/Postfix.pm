#!/usr/bin/perl

package Mail::Log::Parse::Postfix;
{
=head1 NAME

Mail::Log::Parse::Postfix - Parse and return info in Postfix maillogs

=head1 SYNOPSIS

  use Mail::Log::Parse::Postfix;

(See L<Mail::Log::Parse> for more info.)

=head1 DESCRIPTION

This is a subclass of L<Mail::Log::Parse>, which handles parsing for
Postfix mail logs.

=head1 USAGE

=cut

use strict;
use warnings;
use Scalar::Util qw(refaddr);
use Time::Local;
use Mail::Log::Parse;
use Mail::Log::Exceptions;
use base qw(Mail::Log::Parse Exporter);

BEGIN {
    use Exporter ();
    use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = '1.0';
    #Give a hoot don't pollute, do not export more than needed by default
    @EXPORT      = qw();
    @EXPORT_OK   = qw();
    %EXPORT_TAGS = ();
}

# A constant, to convert month names to month numbers.
my %MONTH_NUMBER = (	Jan		=> 0
						,Feb	=> 1
						,Mar	=> 2
						,Apr	=> 3
						,May	=> 4
						,Jun	=> 5
						,Jul	=> 6
						,Aug	=> 7
						,Sep	=> 8
						,Oct	=> 9
						,Nov	=> 10
						,Dec	=> 11
					);

# We are going to assume we are only run once a day.  (Actually, since we only
# ever use the _year_...)
my @CURR_DATE = localtime;

#
# Define class variables.  Note that they are hashes...
#

my %log_info;

#
# DESTROY class variables.
#
### IF NOT DONE THERE IS A MEMORY LEAK.  ###

sub DESTROY {
	my ($self) = @_;
	
	delete $log_info{refaddr $self};
	
	return;
}

=head2 next

Returns a hash of the next line of postfix log data.

Hash keys are:

	delay_before_queue, delay_connect_setup, delay_in_queue, 
	delay_message_transmission, from, host, id, msgid, pid, program, 
	relay, size, status, text, timestamp, to, total_delay

All keys are garunteed to be present.  'program', 'pid', 'host', 'timestamp',
'id' and 'text' are garunteed to have a value.

The 'text' key will have all of the log text B<after> the standard Postfix
header.  (All of which is in the other keys that are required to have a value.)

=cut

sub next {
	my ($self) = @_;

	# The hash we will return.
	my %line_info = ( program => '' );

	# Some temp variables.
	my $line;
	my @line_data;

	# In a mixed-log enviornment, we can't count on any particular line being
	# something we can parse.  Keep going until we can.
	while ( $line_info{program} !~ m/postfix/ ) {
		# Read the line.
		$line = $self->_get_data_line() or return undef;

		# Start parsing.
		@line_data = split ' ', $line, 7;

		# Program name and pid.
		($line_info{program}, $line_info{pid}) = $line_data[4] =~ m/([^[]+)\[(\d+)\]/;
	}

	# Ok, let's update our info.
	$self->_set_current_position_as_next_line();

	# First few fields are the date.  Convert back to Unix format...
	{	# We don't need all these temp variables hanging around.
		my ($log_hour, $log_minutes, $log_seconds) = split /:/, $line_data[2];
		$line_info{timestamp} = timelocal($log_seconds, $log_minutes, $log_hour, $line_data[1], $MONTH_NUMBER{$line_data[0]}, $CURR_DATE[5]);
	}

	# Machine Hostname
	$line_info{host} = $line_data[3];

	# Connection ID
	if ( $line_data[5] =~ /([^:]+):/ ) {
		$line_info{id} = $1;
	}
	else {
		$line_info{id} = undef;
	}

	# The full rest is given as text.
	if (defined($line_info{id})) {
		$line_info{text} = $line_data[6];
	}
	else {
		$line_info{text} = join ' ', @line_data[5..$#line_data];
	}
	chomp $line_info{text};

	# Stage two of parsing.
	# (These may or may not return any info...)

	# To address
	($line_info{to}) = $line_info{text} =~ m/to=([^,]*),/;

	# From address
	($line_info{from}) = $line_info{text} =~ m/from=([^,]*),/;

	# Relay
	($line_info{relay}) = $line_info{text} =~ m/relay=([^,]*),/;

	# Status
	($line_info{status}) = $line_info{text} =~ m/status=(.*)$/;

	# Size
	($line_info{size}) = $line_info{text} =~ m/size=([^,]*),/;

	# Delays
	($line_info{delay_before_queue}, $line_info{delay_in_queue}, $line_info{delay_connect_setup}, $line_info{delay_message_transmission} )
		= $line_info{text} =~ m{delays=([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+),};
	($line_info{total_delay}) = $line_info{text} =~ m/delay=([\d.]+),/;

	# Message ID
	($line_info{msgid}) = $line_info{text} =~ m/message-id=(.*)$/;

	# Return the data.
	return \%line_info;
}

=head1 BUGS

None known at the moment.

=head1 REQUIRES

Scalar::Util, Time::Local, Mail::Log::Parse, Mail::Log::Exceptions

=head1 AUTHOR

Daniel T. Staal

DStaal@usa.net

=head1 SEE ALSO

L<Mail::Log::Parse>, for the main documentation on this module set.

=head1 HISTORY

Oct 6, 2008 - Inital version.

=head1 COPYRIGHT and LICENSE

Copyright (c) 2008 Daniel T. Staal. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

This copyright will expire in 30 years, or 5 years after the author's
death, whichever is longer.

=cut

# End module package.
}
1;