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

my $rs = 0;
my $result = 0;
my $db = iMSCP::Database->factory();
my $plugin = Plugin::LetsEncrypt->getInstance();

$db->doQuery(
    'q',
    'TRUNCATE ssl_certs'
);

# Should insert a certificate
$rs = $plugin->_updateSelfSignedCertificate('dmn', 1);
is($rs, 0, "LetsEncrypt::_updateSelfSignedCertificate No records");

$result = $db->doQuery(
    'cert_id',
    'SELECT * FROM ssl_certs'
);
is (scalar keys %{$result}, 1, "DB has one record");

# Should pass validation and do no harm
$rs = $plugin->_updateSelfSignedCertificate('dmn', 1);
is($rs, 0, "LetsEncrypt::_updateSelfSignedCertificate Existing record");

# Remove the private key and certificate from an exiting record.
$result = $db->doQuery(
    'q',
    "UPDATE ssl_certs SET private_key='',certificate='' WHERE domain_type=? AND domain_id=?",
    'dmn', 1
);
$rs = $plugin->_updateSelfSignedCertificate('dmn', 1);
is($rs, 0, "LetsEncrypt::_updateSelfSignedCertificate Invalid record");
