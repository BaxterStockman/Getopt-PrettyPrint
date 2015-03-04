package Getopt::PrettyPrint;

use strict;
use warnings;
use utf8;

use Carp qw(croak);
use Exporter qw(import);
use IPC::Cmd qw(run can_run);
use List::Util qw(max);
use Module::Load::Conditional qw(can_load);

use constant {
	DEFAULT_TERM_WIDTH	=> 80,
	FLAG_PADDING		=> 4,
};

our @EXPORT = qw(pretty_print_options);

BEGIN {
	my $use_list = {
		'Term::ReadKey'	=> undef,
	};

	my $get_terminal_width_glob = \*{_get_terminal_width};
	if ( can_load('modules' => $use_list) ) {
		$$get_terminal_width_glob = sub {
			return eval {
				(Term::ReadKey::GetTerminalSize())[0]
			} // DEFAULT_TERM_WIDTH();
		};
	}
	elsif ( can_run('stty') ) {
		$$get_terminal_width_glob = sub {
			my $buffer;
			if ( scalar run(
				'command'	=> [qw(stty size)],
				'buffer'	=> \$buffer,
			) ) {
				# Terminal width is the whitespace-separated
				# field output by 'stty size'
				return (split /\s+/, $buffer)[1];
			}
			else {
				return DEFAULT_TERM_WIDTH;
			}
		};
	}
	else {
		# 'use constant' constants are just subroutines.
		$$get_terminal_width_glob = \&DEFAULT_TERM_WIDTH;
	}
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sub pretty_print_options {
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
=head2 pretty_print_options

N.B. The order in which pretty_print_options prints options and descriptions is
undefined when they are passed as a hash reference rather than a pair of list
references.

=cut
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	my ( $options_ref, $description_ref ) = @_;

	my @options;
	my @descriptions;

	if ( ref $options_ref ne 'ARRAY' or ref $description_ref ne 'ARRAY' ) {
		croak sprintf "Usage: %s([GETOPT_SPEC, ...], [DESCRIPTION, ...])",
			(caller 0)[3];

	}
	else {
		@options = @{$options_ref};
		@descriptions = @{$description_ref};
	}

	my @option_flags = map { [split /\|/, $_ =~ s/\A(.+)(!|=.*)\z/$1/r] } @options;

	if ( scalar @option_flags != scalar @descriptions ) {
		croak sprintf "Number of options does not match number of descriptions.\n%s",
			(sprintf "Usage: %s([GETOPT_SPEC, ...], [DESCRIPTION, ...])",
			(caller 0)[3]);
	}

	my @option_lines;
	foreach my $flag_group ( @option_flags ) {
		push @option_lines, join ', ', map {
			length $_ == 1 ? "-$_" : "--$_"
		} @$flag_group;
	}

	my $width = _get_terminal_width();
	my $longest_opt_len = max map { length } @option_lines;
	my $remaining_len = $width - $longest_opt_len - FLAG_PADDING();

	# XXX The arguments 'opt' and 'desc' are important: when
	# &default_format calls the string form of 'eval', the string "our
	# (\$$opt_name, \$$desc_name)" will evaluate to 'our ($opt, $desc)',
	# and each of those two package variables will contain values assigned
	# to those variables in this function.
	_define_format($longest_opt_len, $remaining_len, 'opt', 'desc');

	# Select the current report format
	$~ = 'OPTION_FORMAT';
	# Turn on autoflush so that output is printed immediately
	$| = 1;

	for my $i ( 0..$#option_lines) {
		# These need to be package variables; otherwise, they won't be
		# defined when we try to write the format
		our $opt = $option_lines[$i];
		our $desc = $descriptions[$i];

		# Output the format
		write();
	}
}

sub _define_format {
	my ( $opt_len, $desc_len, $opt_name, $desc_name ) = @_;

	my $option_format = '@' . '<' x $opt_len;
	my $blanks = ' ' x ((length $option_format) - 2);
	my $description_format = '^' . '<' x $desc_len;

my $format = <<"EOFORMAT";
our (\$$opt_name, \$$desc_name);
format OPTION_FORMAT =
$option_format $description_format
\$$opt_name,\$$desc_name
~~$blanks $description_format
\$$desc_name
.
EOFORMAT

	# The format has to be evaluated at runtime in order to properly
	# reflect the current width of the user's terminal
	#
	# Perl warns if a format is redefined, so shut that off.
	{
		no warnings 'redefine';
		eval $format;
	}
}

my @options = (
	'one!',
	'two=s@',
	'f|four=i',
);

my @descriptions = (
	'This that the other something else blah blah blah yada yada',
	'More of the same.  Are you really reading this?  It does not seem you are.  That is unfortunate as this stuff is super -- I mean SUPER -- interesting.',
	'Huh.  Wonder what happened to --three?',
);


pretty_print_options(\@options, \@descriptions);
