use diagnostics; # this gives you more debugging information
use warnings;    # this warns you of bad practices
use strict;      # this prevents silly errors
use Cwd 'abs_path';
use Test::More qw( no_plan ); # for the is() and isnt() functions

use lib (abs_path('../../backend'), abs_path('../../../../../engine/PerlLib'));

use iMSCP::Bootstrapper;

use iMSCP::Debug qw/ debug error /;
use iMSCP::Execute;

my $bootstrapper = iMSCP::Bootstrapper->getInstance();
$bootstrapper->getInstance()->boot(
    {
        mode            => 'backend',
        nolock          => 1,
        norequirements  => 1,
        config_readonly => 1
    }
);

sub _lookup
{
    # TODO Add $self
    my ($domain) = @_;
    my $rs = 0;

    my ($stdout, $stderr);
    my $command = "host " . $domain . " 8.8.8.8";
    $rs = execute(
        $command,
        \$stdout, \$stderr
    );
    # print( $command );
    # print( $stdout ) if $stdout;
    return 1 if $stdout =~ /Host \w+ not found/m;
    return 0 if $stdout =~ /is an alias for/m;
    return 0 if $stdout =~ /has address/m;

    return 2;
}

ok (_lookup("cambodia.sil.org") == 0, 'domain exists');
ok (_lookup("www.cambodia.sil.org") != 0, 'domain does not exist');

ok (_lookup("arketec.com") == 0, 'domain exists');
ok (_lookup("www.arketec.com") == 0, 'domain exists');
ok (_lookup("bogus.minecraftfarm.com") != 0, 'domain does not exist');
