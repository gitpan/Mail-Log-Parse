#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use Test::Exception; 
use Time::Local;
use Mail::Log::Parse::Postfix;
use Mail::Log::Exceptions;

if ( eval{ require IO::Uncompress::AnyUncompress } and eval{ require IO::Uncompress::Gunzip } ) {
	plan( tests => 107 );
}
else {
	plan( skip_all => 'Need IO::Uncompress::AnyUncompress and IO::Uncompress::Gunzip installed.');
}

# We'll need this value over and over.
( undef, undef, undef, undef, undef, my $year) = localtime;

# The keys list.
my @keys = sort qw(to from relay pid msgid program host status id timestamp text size delay_before_queue 
					delay_in_queue delay_connect_setup delay_message_transmission total_delay);

### Test the non-working. ###
{
my $object;
throws_ok {$object = Mail::Log::Parse::Postfix->new({'log_file' => 't/log.gz'})} 'Mail::Log::Exceptions::LogFile';

	# This is going to test
	# a file that exists, but we can't read...
chmod (0000, 't/data/log.gz');
throws_ok {$object = Mail::Log::Parse::Postfix->new({'log_file' => 't/data/log.gz'})} 'Mail::Log::Exceptions::LogFile';
chmod (0644, 't/data/log.gz');	# Make sure we set it back at the end.

# Now we test an unreadable bzip file.
throws_ok {$object = Mail::Log::Parse::Postfix->new({'log_file' => 't/data/log_bad.bz2'})} 'Mail::Log::Exceptions::LogFile';
}

my $object = Mail::Log::Parse::Postfix->new();

$object->set_logfile('t/data/log.gz');

is($object->get_line_number(), 0, 'Starting line number.');

# Back from the beginning.
{
	my $result = $object->previous();
	is($result, undef, 'Back from start.');
}

# A quick test of the first line.
{
my $result = $object->next();

my @result_keys = sort keys %$result;
is_deeply( \@result_keys, \@keys, 'Hash key list.');
is($object->get_line_number(), 1, 'Read one line.');
is($result->{to}, '<00000000@acme.gov>', 'Read first to.');
is($result->{relay}, '127.0.0.1[127.0.0.1]:10025', 'Read first relay.');
is($result->{program}, 'postfix/smtp', 'Read first program.');
is($result->{pid}, '5727', 'Read first process ID.');
is($result->{host}, 'acmemail1', 'Read first hostname.');
is($result->{status}, 'sent (250 OK, sent 48A8F422_13987_12168_1 6B1B62259)', 'Read first status.');
is($result->{id}, 'CF6C9214B', 'Read first ID.');
my $timestamp = timelocal(38, 01, 00, 18, 7, $year);
is($result->{timestamp}, $timestamp, 'Read first timestamp');
is($result->{text}, 'to=<00000000@acme.gov>, relay=127.0.0.1[127.0.0.1]:10025, delay=0.63, delays=0.54/0/0/0.09, dsn=2.0.0, status=sent (250 OK, sent 48A8F422_13987_12168_1 6B1B62259)', 'Read first text.');
is($result->{delay_before_queue}, '0.54', 'Read first delay before queue.');
is($result->{delay_in_queue}, '0', 'Read first delay in queue.');
is($result->{delay_connect_setup}, '0', 'Read first delay connect setup.');
is($result->{delay_message_transmission}, '0.09', 'Read first delay message transmission.');
is($result->{total_delay}, '0.63', 'Read first total delay.');
is($result->{size}, undef, 'Read first size.');
}

# Go forward, testing iterator.
{
	lives_ok { is($object->go_forward(2), 1, 'Going forward.') } 'Going forwards.';
	is($object->get_line_number(), 3, 'Go forward line number.');
	
	my $result = <$object>;

	my @result_keys = sort keys %$result;
	is_deeply( \@result_keys, \@keys, 'Read after skip: Hash key list.');
	is($object->get_line_number(), 4, 'Read after skip: Line number.');
	is($result->{to}, undef, 'Read after skip: To');
	is($result->{relay}, undef, 'Read after skip: Relay');
	is($result->{program}, 'postfix/smtpd', 'Read after skip: Program');
	is($result->{pid}, '5819', 'Read after skip: pid');
	is($result->{host}, 'acmemail1', 'Read after skip: hostname');
	is($result->{status}, undef, 'Read after skip: status');
	is($result->{id}, '7326D2B54', 'Read after skip: id');
	my $timestamp = timelocal(38, 01, 00, 18, 7, $year);
	is($result->{timestamp}, $timestamp, 'Read after skip: timestamp');
	is($result->{text}, 'client=unknown[10.0.80.60]', 'Read after skip: text');
	is($result->{delay_before_queue}, undef, 'Read after skip delay before queue.');
	is($result->{delay_in_queue}, undef, 'Read after skip delay in queue.');
	is($result->{delay_connect_setup}, undef, 'Read after skip delay connect setup.');
	is($result->{delay_message_transmission}, undef, 'Read after skip delay message transmission.');
	is($result->{total_delay}, undef, 'Read after skip total delay.');
	is($result->{size}, undef, 'Read after skip: size');
}

# Read another line.  (This happens to be a connect, which are odd.)
{
	my $result = $object->next();

	my @result_keys = sort keys %$result;
	is_deeply( \@result_keys, \@keys, 'Read connect: Hash key list.');
	is($object->get_line_number(), 5, 'Read connect: Line number.');
	is($result->{to}, undef, 'Read connect: To');
	is($result->{relay}, undef, 'Read connect: Relay');
	is($result->{program}, 'postfix/smtpd', 'Read connect: Program');
	is($result->{pid}, '5748', 'Read connect: pid');
	is($result->{host}, 'acmemail1', 'Read connect: hostname');
	is($result->{status}, undef, 'Read connect: status');
	is($result->{id}, undef, 'Read connect: id');
	my $timestamp = timelocal(38, 01, 00, 18, 7, $year);
	is($result->{timestamp}, $timestamp, 'Read connect: timestamp');
	is($result->{text}, 'connect from localhost.localdomain[127.0.0.1]', 'Read connect: text');
	is($result->{size}, undef, 'Read connect: size');
}

# Let's go back again...
{
	lives_ok {is($object->go_backward(), 1, 'Going backward.') } 'Going backwards.';
	is($object->get_line_number(), 4, 'Go back line number.');
}

# Seek further back.
{
	lives_ok {is($object->go_backward(5), 1, 'All the way back.') } 'All the way back.';
	is($object->get_line_number(), 0, 'Back to start line number.');

	my $result = $object->next();

	my @result_keys = sort keys %$result;
	is_deeply( \@result_keys, \@keys, 'Read after backskip: Hash key list.');
	is($object->get_line_number(), 1, 'Read after backskip: Line number.');
	is($result->{to}, '<00000000@acme.gov>', 'Read after backskip: To');
	is($result->{from}, undef, 'Read after backskip: From');
	is($result->{relay}, '127.0.0.1[127.0.0.1]:10025', 'Read after backskip: Relay');
	is($result->{program}, 'postfix/smtp', 'Read after backskip: Program');
	is($result->{pid}, '5727', 'Read after backskip: pid');
	is($result->{host}, 'acmemail1', 'Read after backskip: hostname');
	is($result->{status}, 'sent (250 OK, sent 48A8F422_13987_12168_1 6B1B62259)', 'Read after backskip: status');
	is($result->{id}, 'CF6C9214B', 'Read after backskip: id');
	my $timestamp = timelocal(38, 01, 00, 18, 7, $year);
	is($result->{timestamp}, $timestamp, 'Read after backskip: timestamp');
	is($result->{text}, 'to=<00000000@acme.gov>, relay=127.0.0.1[127.0.0.1]:10025, delay=0.63, delays=0.54/0/0/0.09, dsn=2.0.0, status=sent (250 OK, sent 48A8F422_13987_12168_1 6B1B62259)');
	is($result->{size}, undef, 'Read after backskip: size');
}

# Seek forward.
{
	lives_ok {is($object->go_forward(), 1, 'Skip forward.') } 'Skip forward.';
	is($object->get_line_number(), 2, 'Skipped forward two.');
	
	my $result = $object->next();

	my @result_keys = sort keys %$result;
	is_deeply( \@result_keys, \@keys, 'Read after skip: Hash key list.');
	is($object->get_line_number(), 3, 'Read after skip: Line number.');
	is($result->{to}, undef, 'Read after skip: To');
	is($result->{from}, '<00000001@baz.acme.gov>', 'Read after skip: From');
	is($result->{relay}, undef, 'Read after skip: Relay');
	is($result->{program}, 'postfix/qmgr', 'Read after skip: Program');
	is($result->{pid}, '20508', 'Read after skip: pid');
	is($result->{host}, 'acmemail1', 'Read after skip: hostname');
	is($result->{status}, undef, 'Read after skip: status');
	is($result->{id}, '6B1B62259', 'Read after skip: id');
	my $timestamp = timelocal(38, 01, 00, 18, 7, $year);
	is($result->{timestamp}, $timestamp, 'Read after skip: timestamp');
	is($result->{text}, 'from=<00000001@baz.acme.gov>, size=84778, nrcpt=7 (queue active)', 'Read after skip: text');
	is($result->{size}, '84778', 'Read after skip: size');

}

# Previous line.
{
	my $result = $object->previous();

	my @result_keys = sort keys %$result;
	is_deeply( \@result_keys, \@keys, 'Read previous: Hash key list.');
	is($object->get_line_number(), 2, 'Read previous: Line number.');
	is($result->{to}, undef, 'Read previous: To');
	is($result->{from}, undef, 'Read previous: From');
	is($result->{relay}, undef, 'Read previous: Relay');
	is($result->{program}, 'postfix/smtpd', 'Read previous: Program');
	is($result->{pid}, '5833', 'Read previous: pid');
	is($result->{host}, 'acmemail1', 'Read previous: hostname');
	is($result->{status}, undef, 'Read previous: status');
	is($result->{id}, undef, 'Read previous: id');
	my $timestamp = timelocal(38, 01, 00, 18, 7, $year);
	is($result->{timestamp}, $timestamp, 'Read previous: timestamp');
	is($result->{text}, 'disconnect from localhost.localdomain[127.0.0.1]');
	is($result->{size}, undef, 'Read previous: size');
}

# Seek forward.
{
	lives_ok {is($object->go_forward(2), 1, 'Skip forward.') } 'Skip forward.';
	is($object->get_line_number(), 4, 'Skipped forward two.');
}


# Read to exaustion.
{
	$object->go_to_end();
	is($object->get_line_number(), 900, 'Read to end of file.');
}

# Go back to start.
{
	$object->go_to_beginning();
	is($object->get_line_number(), 0, 'Skip to begining.');
}
