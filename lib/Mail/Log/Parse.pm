#!/usr/bin/perl

package Mail::Log::Parse;
{
=head1 NAME

Mail::Log::Parse - Parse and return info in maillogs

=head1 SYNOPSIS

  use Mail::Log::Parse;

  $object = Mail::Log::Parse->new({  log_file => '/path/to/logfile'  });
  %line_info = %{object->next()};
  
  $line_num = $object->get_line_num();
  
  if ( $object->go_forward($amount) ) {
    ...
  }
  
  if ( $object->go_backward($amount) ) {
    ...
  }
  
  %line_info = %{object->previous()};

=head1 DESCRIPTION

This is the root-level module for a generic mail log file parser.  It is capable
of opening either a compressed or uncompressed logfile, and either stepping
through it line by line, or seaking around in it based on the logical lines.
(Lines not pertaining to the type of log currently being searched are skipped,
as if they don't exist.)

On it's own it doesn't actually do much: You'll need a subclass that can
parse a particular program's log entries.  But such subclasses are designed to
be easy to write and use.

=head1 USAGE

This is an object-oriented module.  Avalible object methods are below.

In a string context, it will return a string specifying the path to the file
and the current line number.  In a boolean context, it will return whether it
has been correctly initilized.  (Whether it has a file.)  Numeric context throws
an error.

Oh, and interator context ('<>') returns the same as 'next'...

=cut

use strict;
use warnings;
use Scalar::Util qw(refaddr blessed);
use File::Basename;
use IO::File;
use File::Temp 0.17;
use Mail::Log::Exceptions;
use base qw(Exporter);


BEGIN {
    use Exporter ();
    use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA);
    $VERSION     = '1.1.0';
    #Give a hoot don't pollute, do not export more than needed by default
    @EXPORT      = qw();
    @EXPORT_OK   = qw();
    %EXPORT_TAGS = ();
}

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

#
# Set the coercions to something useful.
#

use overload (
	# Strings overload to the path and line number.
	qw{""} => sub { my ($self) = @_;
					return  blessed($self)
							.' File: '
							.$log_info{refaddr $self}{'filename'}
							.' Line: '
							.$log_info{refaddr $self}{'current_line'};
					},
	
	# Boolean overloads to if we are usable.  (Have a filehandle.)
	qw{bool} => sub { my ($self) = @_;
						return defined($log_info{refaddr $self}{'filehandle'});
					},
	
	# Numeric context just doesn't mean anything.  Throw an error.
	q{0+} => sub { Mail::Log::Exceptions->throw(q{Can't get a numeric value of a Mail::Log::Parse.} );
				},
	
	# Heh.  Iterator context is the same as 'next'...
	q{<>} => sub { my ($self) = @_; return $self->next(); },
	
	# Perl standard for everything else.
	fallback => 1,
			);

=head2 new (constructor)

The base constructor for the Mail::Log::Parse classes.  It takes an (optional)
hash containing path to the logfile as an arugment, and returns the new object.

Example:

  $object = Mail::Log::Parse->new({  log_file => '/path/to/logfile'  });

Note that it is an error to call any method other than C<set_logfile> if you
have not passed it in the constructor.

=cut

sub new
{
    my ($class, $parameters_ref) = @_;

    my $self = bless \do{my $anon}, $class;

	# Log info.
	if ( defined($parameters_ref->{'log_file'}) ) {
		$self->set_logfile($parameters_ref->{'log_file'});  # Better to keep validation together.
	}

	return $self;
}

=head2 set_logfile

Sets the logfile that this object will attempt to parse.  It will throw
exceptions if it can't open the file for any reason, and will return true on
success.

Files can be compressed or uncompressed: If they are compressed, then
C<IO::Uncompress::AnyUncompress> must be installed with the relevant
decompression libraries.  Currently only 'tgz', 'zip', 'gz', and 'bz2' archives
are supported, but there is no technical reason not to support more.  (It just
keeps a couple of lines of code shorter.)

Note that to support seeking in the file the log will be uncompressed to disk
before it is read: If there is insufficent space to do so, we may have trouble.
It also means this method may take a while to return for large compressed logs.

Example:

  $object->set_logfile('path/to/file');

=cut

sub set_logfile {
	my ($self, $new_name) = @_;
	
	# Check to make sure the file exitsts,
	# and then that we can read it, before accpeting the filename.
	if ( -e $new_name ) {
		if ( -r $new_name ) {
			$log_info{refaddr $self}{'filename'} = $new_name;

			# We'll check the extension to see if it is compressed.
			my (undef, undef, $suffix) = fileparse($new_name, qw(tgz zip gz bz2));
			if ( $suffix ) {

				# Since we only need uncompress symantics right here, we'll
				# only load them if we need them.  Neat, huh?
				require IO::Uncompress::AnyUncompress;
				IO::Uncompress::AnyUncompress->import( qw(anyuncompress) );

				# If it is compressed, uncompress to a temp file and use that.
				my $temp = new File::Temp();
				anyuncompress($new_name, $temp)
					or Mail::Log::Exceptions::LogFile->throw("Unable to uncompress logfile $new_name: ". $IO::Uncompress::AnyUncompress::AnyUncompressError ."\n");
				$temp->seek(0,0)
					or Mail::Log::Exceptions::LogFile->throw("Unable to seek to beginning of temp file.\n");
				$log_info{refaddr $self}{'filehandle'} = $temp;
			}
			else {
				# If it wasn't compressed, open it direct.
				$log_info{refaddr $self}{'filehandle'} = IO::File->new($new_name, '<')
					or Mail::Log::Exceptions::LogFile->throw("Unable to open file $new_name: $!\n");
			}

			# Init some location information on the file.
			$log_info{refaddr $self}->{'current_line'} = 0;
			delete $log_info{refaddr $self}{'line_positions'};
			${$log_info{refaddr $self}{'line_positions'}}[$log_info{refaddr $self}{'current_line'}] = $log_info{refaddr $self}{'filehandle'}->getpos();
		}
		else {
			Mail::Log::Exceptions::LogFile->throw("Log file $new_name is not readable.\n");
		}
	}
	else {
		Mail::Log::Exceptions::LogFile->throw("Log file $new_name does not exist.\n");
	}

	return 1;
}

=head2 next

Returns a reference to a hash of the next parsable line of the log, or undef on 
end of file/failure.

There are a couple of required keys that any parser must implement:

timestamp, program, id, text.

Where C<timestamp> must the the unix timestamp, C<program> must be the name of
the program that reported the logline (Sub-programs are recommened to be listed,
if possible), C<id> is the tracking ID for that message, as reported by the
program, and C<text> is the text following any 'standard' headers.  (Usually,
minus those already required keys.)

This version is just a placeholder: It will return a 
'Mail::Log::Exceptions::Unimplemented' exception if called.  It is expected to
be overridden by the subclass.  (And is the only method needed to be overridden.)

Other 'standard' fields that are expected in a certain format (but are not
required to always be present) are 'from', 'to', 'size', 'subject'.  'to'
should point to an array of addresses.  (As listed in the log.  That includes 
angle brackets, usually.)

Example:

  while $hash_ref ( $object->next() ) {
    ...
  }

or...

  while $hash_ref ( <$object> ) {
    ...
  }

=cut

sub next {
	my ($self) = @_;
	
	Mail::Log::Exceptions::Unimplemented->throw("Method 'next' needs to be implemented by the subclass.\n");
}

=head2 previous

Returns a reference to a hash of the previous line of the log, or undef on
failure/beginning of file.

See C<next> for details: It works nearly exactly the same.  (In fact, it calls
next as a parser.)

=cut

sub previous {
	my ($self) = @_;

	# Check if we can.
	if ( $log_info{refaddr $self}->{'current_line'} <= 1 ) {
		return undef;
	}

	# Go back two lines
	$self->go_backward(2);

	# And read forward one, returning that.
	return $self->next();
}

=head2 go_forward

Goes forward a specifed number of (logical) lines, or 1 if unspecified.  It will
throw an error if it fails to seek as requested.

Returns true on success.

Example:

  $object->go_forward(4);

=cut

sub go_forward {
	my ($self, $lines) = @_;
	
	# Just because I'm paranoid.
	$lines ||= 1;
	
	# If we've read the line before, go straight to it.
	if ( ${$log_info{refaddr $self}{'line_positions'}}[($log_info{refaddr $self}->{'current_line'}+$lines)] ) {
		$log_info{refaddr $self}{'filehandle'}->setpos(${$log_info{refaddr $self}{'line_positions'}}[($log_info{refaddr $self}->{'current_line'}+$lines)])
			or Mail::Log::Exceptions::LogFile->throw("Error seeking to position: $!\n");
		$log_info{refaddr $self}->{'current_line'} = $log_info{refaddr $self}->{'current_line'} + $lines;
	}
	else {
		# Otherwise, read until we get to it.
		foreach ( 1..$lines ) {
			$self->next();
		}
	}
	return 1;
}

=head2 go_backward

Goes backward a specifed number of (logcial) lines, or 1 if unspecified.  It will 
throw an error if it fails to seek as requested.

If the seek would go beyond the beginning of the file, it will go to the
beginning of the file.

Returns true on success.

Example:

  $object->go_backward(4);

=cut

sub go_backward {
	my ($self, $lines) = @_;

	# Just because I'm paranoid.
	$lines ||= 1;

	# If the line exits, go straight to it.
	if ( ($log_info{refaddr $self}->{'current_line'} - $lines ) > 0 ) {
		$log_info{refaddr $self}{'filehandle'}->setpos(${$log_info{refaddr $self}{'line_positions'}}[($log_info{refaddr $self}->{'current_line'}-$lines)])
			or Mail::Log::Exceptions::LogFile->throw("Error seeking to position: $!\n");
		$log_info{refaddr $self}{'current_line'} -= $lines;
	}
	else {
		#If they've asked us to go beyond the beginning of the file, just go to the beginning.
		$log_info{refaddr $self}{'filehandle'}->setpos(${$log_info{refaddr $self}{'line_positions'}}[0])
			or Mail::Log::Exceptions::LogFile->throw("Error seeking to position: $!\n");
		$log_info{refaddr $self}->{'current_line'} = 0;
	}
	return 1;
}

=head2 go_to_beginning

Goes to the beginning of the file, no matter how far away that is.

Returns true on success.

=cut

sub go_to_beginning {
	my ($self) = @_;

	$log_info{refaddr $self}{'filehandle'}->setpos(${$log_info{refaddr $self}{'line_positions'}}[0])
		or Mail::Log::Exceptions::LogFile->throw("Error seeking to beginning: $!\n");
	$log_info{refaddr $self}->{'current_line'} = 0;

	return 1;
}

=head2 go_to_end

Goes to the end of the file, no matter where it is.

This attempts to be efficient about it, skipping where it can.

Returns true on success.

=cut

sub go_to_end {
	my ($self) = @_;
	
		$log_info{refaddr $self}{'filehandle'}->setpos(${$log_info{refaddr $self}{'line_positions'}}[-1])
			or Mail::Log::Exceptions::LogFile->throw("Error seeking to end: $!\n");
		$log_info{refaddr $self}->{'current_line'} = $#{$log_info{refaddr $self}{'line_positions'}};

	while ( $self->next() ) {
		1;
	}

	return 1;
}

=head2 get_line_number

Returns the current logical line number.

Note that line numbers start at zero, where 0 is the absolute beginning of the
file.

Example:

  $line_num = $object->get_line_number();

=cut

sub get_line_number {
	my ($self) = @_;
	return $log_info{refaddr $self}{'current_line'};
}

#
# These are semi-private methods: They are for the use of subclasses only.
#

=head1 UTLITY METHODS

The following methods are not for general consumption: They are specifically
provided for use in implementing subclasses.  Using them incorrectly, or
outside a subclass, can get the object into an invalid state.

B<ONLY USE IF YOU ARE IMPLEMENTING A SUBCLASS.>

=head2 _set_current_position_as_next_line

Sets the current position in the file as the next 'line' position in sequence.

Call once you have determined that the current line of data (as returned from
C<_get_data_line>) is parsable in the currently understood format.

=cut

sub _set_current_position_as_next_line { 
	my ($self) = @_;

	$log_info{refaddr $self}{'current_line'} += 1;
	${$log_info{refaddr $self}{'line_positions'}}[$log_info{refaddr $self}->{'current_line'}] = $log_info{refaddr $self}{'filehandle'}->getpos()
		or Mail::Log::Exceptions::LogFile->throw("Unable to get current file position: $!\n");
	return;
}

=head2 _get_data_line

Returns the next line of data, as a string, from the logfile.  This is raw data
from the logfile, seperated by the current input seperator.

=cut

sub _get_data_line {
	my ($self) = @_;
	return $log_info{refaddr $self}{'filehandle'}->getline();
}

=head2 Suggested usage:

Suggestion on how to use the above two methods to implement a 'next' routine in
a subclass:

  sub next {
	my ($self) = @_;

	# The hash we will return.
	my %line_info = ( program => '' );

	# Some temp variables.
	my $line;

	# In a mixed-log enviornment, we can't count on any 
	# particular line being something we can parse.  Keep
	# going until we can.
	while ( $line_info{program} !~ m/$program_name/ ) {
		# Read the line.
		$line = $self->_get_data_line() or return undef;

		# Program name.
		$line_info{program} = $line ~= m/$regrex/;
	}

	# Ok, let's update our info.
	$self->_set_current_position_as_next_line();

	# Continue parsing
	...

=cut

#
# Fully private methods.
#

=head1 BUGS

C<go_forward> and C<go_backward> at the moment don't test for negative
numbers.  They may or may not work with a negative number of lines: It depends
where you are in the file and what you've read so far.

Those two methods should do slightly better on 'success' testing, to return
better values.  (They basically always return true at the moment.)

=head1 REQUIRES

Scalar::Util, File::Basename, IO::File, File::Temp, Mail::Log::Exceptions

=head1 RECOMMENDS

IO::Uncompress::AnyUncompress

=head1 AUTHOR

Daniel T. Staal

DStaal@usa.net

=head1 SEE ALSO

L<Parse::Syslog::Mail>, which does some of what this module does.  (This module
is a result of running into what that module B<doesn't> support.  Namely
seeking through a file, both forwards and back.)

=head1 HISTORY

Oct 14, 2008 - Found that I need File::Temp of at least version 0.17.

Oct 13, 2008 - Fixed tests so they do a better job of checking if they 
need to skip.

Oct 6, 2008 - Inital version.

=head1 COPYRIGHT and LICENSE

Copyright (c) 2008 Daniel T. Staal. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

This copyright will expire in 30 years, or 5 years after the author's
death, whichever is longer.

=cut
}	# End Package.
1;
