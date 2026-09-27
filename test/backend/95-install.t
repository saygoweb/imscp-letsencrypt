use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use SGWTest qw/ require_root boot plugin /;

# install() puts certbot and its weekly renewal cron job on the host. That is a
# change to the host no other test makes, so it only runs when asked for:
# SGW_DESTRUCTIVE_TESTS=1. Meant for a throwaway CI container.

plan skip_all => 'set SGW_DESTRUCTIVE_TESTS=1 to install certbot on this host' unless $ENV{'SGW_DESTRUCTIVE_TESTS'};
require_root();
boot();

my $plugin = plugin();

# The installer dies outright when a command it runs cannot be found. Caught,
# so that it reads as a failed test with the reason rather than a crashed file.
sub install_rs
{
    my $rs = eval { $plugin->install() };
    diag( "install() died: $@" ) if $@;
    $@ ? 'died' : $rs;
}

is( install_rs(), 0, 'install succeeds' );
ok( !-e '/usr/local/bin/certbot-auto', 'the retired certbot-auto is gone' );
ok( -x '/usr/local/bin/certbot' || -x '/snap/bin/certbot' || -x '/usr/bin/certbot', 'certbot is installed' );
ok( -x '/etc/cron.weekly/letsencrypt', 'the renewal job is installed' );

my $cron = do { local ( @ARGV, $/ ) = '/etc/cron.weekly/letsencrypt'; <> } // '';
my ($certbot) = $cron =~ m{^(\S*certbot) renew}m;
ok( $certbot, 'the renewal job runs certbot renew' );
ok( $certbot && -x $certbot, "and the certbot it runs ($certbot) exists" );

is( install_rs(), 0, 'installing again is harmless' );

done_testing();
