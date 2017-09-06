#!/usr/bin/perl
use File::Path qw/ mkpath remove_tree /;
use Getopt::Long;

# Create a self signed certificate under /etc/letsencrypt for test purposes
# - This only processes the first -d domain option.  It doesn't create a proper csr, is it CN in the Subject only

my $Debug = 99;

my $store_path = '/etc/letsencrypt/live/';

# Pickup the domain name(s) from the -d options on the command line
my $domain = 'test1.local';
@options;
#  certonly --apache --no-bootstrap --non-interactive -v -d
GetOptions(
    'apache', sub {  },
    'domain|d=s', sub { $domain = $_[1] },
    'no-bootstrap', sub {  },
    'non-interactive', sub {  },
    'no-self-update', sub {  },
    'verbose|v', sub {  },
    'help|h', sub { showUsage(); },
    @options,
) or showUsage();

# Ensure the store_path exists
mkpath($store_path);

# Currently we don't process more than one -d option, and the last one wins.  This is typically www.domain so strip the www if present
$domain =~ s/www.//;

my $domain_store_path = '/etc/letsencrypt/live/' . $domain;
my $key_file = $domain_store_path . '/' . 'privkey.pem';
my $cert_file = $domain_store_path . '/' . 'cert.pem';
my $chain_file = $domain_store_path . '/' . 'chain.pem';

# Ensure the domain store path exists
mkpath($domain_store_path);

# Create the key
execute('openssl genrsa -out ' . $key_file . ' 2048');
# Create the cert
execute('openssl req -x509 -new -key ' . $key_file . ' -subj /CN=' . $domain . ' -days 3650 -out ' . $cert_file);
# Create the chain
execute('openssl req -x509 -new -key ' . $key_file . ' -subj /CN=' . $domain . ' -days 3650 -out ' . $chain_file);

# Done

###########
# Functions
###########

sub showUsage {
    print <<EOF
Usage:
    certbot-auto-test [options]
    -d domain
    --non-interactive
    --no-bootstrap
    --no-self-update
    -v --verbose
EOF
}

sub debug {
	my $level = $_[1] || 1;
	if ($Debug >= $level) { 
		my $debugstring = $_[0];
		if ($ENV{"GATEWAY_INTERFACE"}) { $debugstring =~ s/^ /&nbsp&nbsp /; $debugstring .= "<br />"; }
		print localtime(time)." - DEBUG $level - $. - : $debugstring\n";
		}
	0;
}

=item getExitCode([ $ret = $? ])

 Return human exit code

 Param int $ret Raw exit code (default to $?)
 Return int exit code or die on failure

=cut

sub getExitCode(;$)
{
    my $ret = shift // $?;

    if ($ret == -1) {
        debug('Could not execute command');
        return 1;
    }

    if ($ret & 127) {
        debug( sprintf( 'Command died with signal %d, %s coredump', ($ret & 127), ($? & 128) ? 'with' : 'without' ) );
        return $ret;
    }

    $ret = $ret >> 8;
    debug( sprintf( 'Command exited with value: %s', $ret ) ) if $ret != 0;
    $ret;
}

=item execute($command [, \$stdout = undef [, \$stderr = undef]])

 Execute the given command

 Param string|array $command Command to execute
 Param string \$stdout OPTIONAL Variable for capture of STDOUT
 Param string \$stderr OPTIONAL Variable for capture of STDERR
 Return int Command exit code or die on failure

=cut

sub execute($;$$)
{
    my ($command, $stdout, $stderr) = @_;

    defined( $command ) or die( '$command parameter is not defined' );

    if ($stdout) {
        ref $stdout eq 'SCALAR' or die( "Expects a scalar reference as second parameter for capture of STDOUT" );
        $$stdout = '';
    }

    if ($stderr) {
        ref $stderr eq 'SCALAR' or die( "Expects a scalar reference as third parameter for capture of STDERR" );
        $$stderr = '';
    }

    my $multitArgs = ref $command eq 'ARRAY';
    debug( $multitArgs ? "@{$command}" : $command );

    if ($stdout && $stderr) {
        ($$stdout, $$stderr) = capture { system( $multitArgs ? @{$command} : $command); };
        chomp( $$stdout, $$stderr );
    } elsif ($stdout) {
        $$stdout = capture_stdout { system( $multitArgs ? @{$command} : $command ); };
        chomp( $$stdout );
    } elsif ($stderr) {
        $$stderr = capture_stderr { system( $multitArgs ? @{$command} : $command ); };
        chomp( $stderr );
    } else {
        system( $multitArgs ? @{$command} : $command ) != -1 or die(
            sprintf( 'Could not execute command: %s', $! )
        );
    }

    getExitCode();
}

