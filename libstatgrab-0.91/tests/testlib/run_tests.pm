package run_tests;

use strict;
use warnings;

use mix_tests qw(combine_nk);
use Test::More;
use IPC::Cmd ();
use File::Spec ();
use File::Temp ();
use File::Basename;

use Data::Dumper;
use Config;

sub new {
	my ($class, $exename) = @_;
	my %instance = (
			       exename => $exename,
		       );
	my $self = bless( \%instance, $class );
	return $self;
}

sub get_test_functions {
	my ($self) = @_;
	defined($self->{test_functions}) and return $self->{test_functions};
	my $exename = basename($self->{exename});
	# prepare logging to temporary file only during tests running
	my ($logfh, $logfn) = File::Temp::tempfile( TMPDIR => 1, UNLINK => 1,
		SUFFIX => ".log", TEMPLATE => "$exename-XXXXXXXX" );
	close($logfh);
	my ($propfh, $propfn) = File::Temp::tempfile( TMPDIR => 1, UNLINK => 1,
		SUFFIX => ".properties", TEMPLATE => "SG_TEST_XXXXXXX" );
	print $propfh <<EOP;
log4cplus.logger.statgrab=TRACE, LOGFILE

log4cplus.appender.LOGFILE=log4cplus::FileAppender
log4cplus.appender.LOGFILE.File=$logfn
log4cplus.appender.LOGFILE.layout=log4cplus::TTCCLayout
EOP
	$propfh->flush();

	$ENV{SGTEST_LOG_PROPERTIES} = $propfn;
	my $fh;

	open( $fh, "-|", "$self->{exename} -l" ) or die "Can't read from pipe: $!";
	my @funcs = <$fh>;
	close( $fh ) or die "Can't close pipe: $!";
	chomp @funcs;

	$self->{test_functions} = \@funcs;

	return $self->{test_functions};
}

sub init_combinations {
	my ($self) = @_;
	defined( $self->{combinations} ) and return;

	$self->get_test_functions();

	$self->{combinations} = [];
	my $nfuncs = scalar(@{$self->{test_functions}});

	my @funcs_idx = (0 .. ($nfuncs - 1) );
	$self->{combinations}->[0] = [];
	$self->{combinations}->[$nfuncs] = [ [ @funcs_idx ] ];
	$self->{test_function_avail_map} = { map { $_ => $_ } @funcs_idx };

	return;
}

sub get_test_combinations {
	my ($self, $k) = @_;
	my $inv_k;
	my $want_inv = 0;

	$k > 0 or $k <= scalar(@{$self->{test_functions}}) or return;

	$self->init_combinations();
	defined( $self->{combinations}->[$k] ) and return @{ $self->{combinations}->[$k] };

	if( $k > ( scalar(@{$self->{test_functions}}) / 2 ) ) {
		$inv_k = $k;
		$k = scalar(@{$self->{test_functions}}) - $k;
		$want_inv = 1;
	}
	else {
		$inv_k = scalar(@{$self->{test_functions}}) - $k;
	}

	my @combinations = combine_nk( scalar(@{$self->{test_functions}}), $k );
	my @inverse_combinations;
	foreach my $combination (@combinations) {
		my %remain_func_idx = %{$self->{test_function_avail_map}};
		delete @remain_func_idx{@$combination};
		my @inverse_combination = sort { $a <=> $b } keys %remain_func_idx;
		push( @inverse_combinations, \@inverse_combination );
	}

	$self->{combinations}->[$k] = \@combinations;
	$self->{combinations}->[$inv_k] = \@inverse_combinations;

	return $want_inv ? @{ $self->{combinations}->[$inv_k] } : @{ $self->{combinations}->[$k] };
}

sub get_all_test_combinations {
	my ($self) = @_;

	defined( $self->{combinations} ) and return map { @{$_} } @{$self->{combinations}};

	$self->init_combinations();

	my $k = int(scalar(@{$self->{test_functions}}) / 2);
	while( $k > 0 ) {
		$self->get_test_combinations( $k );
		--$k;
	}

	return map { @{$_} } @{$self->{combinations}};
}

sub map_test_variant {
	my ($self,$variant) = @_;
	my $tests = join( ",", map { $self->{test_functions}->[$_] } @{$variant} );
	return $tests;
}

sub get_versions {
	my %versions = (
		OS   => "$^O ($Config::Config{osvers})",
		Perl => "$] ($Config::Config{archname})",
	);

	for my $mod (qw(IPC::Cmd Test::More)) {
		$versions{$mod} = $mod->VERSION();
	}

	return %versions;
}

sub run_tests(\@;\@) {
	my ($self, $args, $variants) = @_;

	ref($variants) eq "ARRAY" or $variants = [ $self->get_all_test_combinations() ];

	plan( tests => scalar(@{$variants}) );

	# complain about environment
	my %versions = get_versions();
	my $indent = 20;
	my @versions = map { sprintf "%s = %s", $_, $versions{$_} } sort keys %versions;
	diag(join(", ", @versions));

	# prepare logging to STDOUT only during tests running
	my ($propfh, $propfn) = File::Temp::tempfile( TMPDIR => 1, UNLINK => 1,
		SUFFIX => ".properties", TEMPLATE => "SG_TEST_XXXXXXX" );
	print $propfh <<EOP;
log4cplus.logger.statgrab=TRACE, STDOUT

log4cplus.appender.STDOUT=log4cplus::ConsoleAppender
log4cplus.appender.STDOUT.layout=log4cplus::TTCCLayout
EOP
	$propfh->flush();

	$ENV{SGTEST_LOG_PROPERTIES} = $propfn;

	foreach my $variant (@{$variants}) {
		ref($variant) eq "ARRAY" or die "Invalid element in variant list";
		my $test_variant = $self->map_test_variant($variant);
		my @exec_args = ($self->{exename}, @$args, '-r', $test_variant);
		my ($success, $error_message, $full_buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(
			command => \@exec_args, verbose => 0, timeout => 60 );
		defined $success or $success = 0;
		my $msg_fn = $success ? Test::More->can("note") : Test::More->can("diag");
		&{$msg_fn}('"' . join('" "', @exec_args) . '"');
		if( "ARRAY" eq ref($stdout_buf) and 0 != scalar(@{$stdout_buf}) ) {
			foreach my $line (@{$stdout_buf}) {
				&{$msg_fn}($line);
			}
		}
		if( "ARRAY" eq ref($stderr_buf) and 0 != scalar(@{$stderr_buf}) ) {
			foreach my $line (@{$stderr_buf}) {
				diag($line);
			}
		}
		cmp_ok( $success, '==', 1, $test_variant );
	}

	done_testing();
}

1;
