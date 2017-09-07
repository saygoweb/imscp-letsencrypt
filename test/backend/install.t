use diagnostics; # this gives you more debugging information
use warnings;    # this warns you of bad practices
use strict;      # this prevents silly errors
use Cwd 'abs_path';
use Test::More qw( no_plan ); # for the is() and isnt() functions

use lib (abs_path('../../backend'), abs_path('../../../../../engine/PerlLib'));

use iMSCP::Bootstrapper;

use LetsEncrypt;

my $bootstrapper = iMSCP::Bootstrapper->getInstance();
$bootstrapper->getInstance()->boot(
    {
        mode            => 'backend',
        nolock          => 1,
        norequirements  => 1,
        config_readonly => 1
    }
);

my $plugin = Plugin::LetsEncrypt->getInstance();
is ($plugin->install(), 0, "install ok");
ok (-e '/usr/local/bin/certbot-auto', 'certbot-auto exists');
