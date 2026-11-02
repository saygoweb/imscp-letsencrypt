use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp;
use Test::More;
use SGWTest qw/ require_root load_plugin /;

# The helpers that touch no state, called on an unblessed instance rather than
# booting the whole i-MSCP backend.

require_root();
ok( load_plugin(), 'the backend module loads' ) or BAIL_OUT( 'cannot load the plugin' );

my $plugin = bless {}, 'Plugin::SGW_LetsEncrypt';

# --- _domainTypeAndId -------------------------------------------------------
# letsencrypt_edit.php writes domain_id = 0 and NULL for the ids it does not use.

is_deeply( [ $plugin->_domainTypeAndId( 7, undef, undef ) ], [ 'dmn', 7 ], 'a domain row is a dmn' );
is_deeply( [ $plugin->_domainTypeAndId( 0, 3, undef ) ], [ 'als', 3 ], 'an alias row is an als' );
is_deeply( [ $plugin->_domainTypeAndId( 0, undef, 5 ) ], [ 'sub', 5 ], 'a subdomain row is a sub' );
is_deeply( [ $plugin->_domainTypeAndId( 0, undef, undef ) ], [ '', 0 ], 'a row with no id is nothing' );

# --- _error / _lastError ----------------------------------------------------

is( $plugin->_error( "  certbot\n  said\tno  " ), 1, '_error returns failure' );
is( $plugin->_lastError(), 'certbot said no', 'whitespace is collapsed so it reads on one line in the panel' );

$plugin->_error( undef );
is( $plugin->_lastError(), 'Unknown error', 'an empty message still reports something' );
$plugin->_error( " \n " );
is( $plugin->_lastError(), 'Unknown error', 'a blank message still reports something' );

$plugin->_error( 'x' x 5000 );
is(
    length $plugin->_lastError(), Plugin::SGW_LetsEncrypt::ERROR_MAX_LENGTH(),
    'a long message is cut to ERROR_MAX_LENGTH'
);
like( $plugin->_lastError(), qr/\.\.\.$/, 'and says it was cut' );

$plugin->_clearError();
ok( !defined $plugin->{'lastError'}, "_clearError forgets the previous domain's error" );

# --- _certbotError ------------------------------------------------------------

is(
    Plugin::SGW_LetsEncrypt::_certbotError( 'a.test', 1, 'out', 'err' ),
    'certbot failed for a.test: err',
    'stderr carries the reason'
);
is(
    Plugin::SGW_LetsEncrypt::_certbotError( 'a.test', 1, 'out', '  ' ),
    'certbot failed for a.test: out',
    'stdout is used when stderr is blank'
);
is(
    Plugin::SGW_LetsEncrypt::_certbotError( 'a.test', 3, undef, undef ),
    'certbot failed for a.test with exit code 3',
    'the exit code is reported when certbot said nothing'
);

# --- _certbotCommand -----------------------------------------------------------
# certbot must be told which lineage to use: left to itself it picks <name>-0001
# when it cannot match one, and the vhost keeps pointing at live/<name> (#40).

my $cmd = $plugin->_certbotCommand( 'a.test', 0 );
like( $cmd, qr/^certbot certonly /, 'certbot is asked for a certificate' );
like( $cmd, qr/ --cert-name '?a\.test'?(?: |$)/, 'in the lineage named after the domain, which the vhost points at' );
like( $cmd, qr/ -d '?a\.test'?(?: |$)/, 'for the domain' );
unlike( $cmd, qr/www/, 'alone when its www name does not resolve' );
like( $plugin->_certbotCommand( 'a.test', 1 ), qr/ --expand -d '?www\.a\.test'?$/, 'and with its www name when it does' );

# --- _wantWWW -------------------------------------------------------------------
# With --cert-name, certbot reissues the lineage for exactly the names it is
# given, so leaving www out by mistake takes it off the certificate the site serves.

my $dir = File::Temp->newdir();
my $withWWW = "$dir/www.pem";
system(
    'openssl', 'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', "$dir/key.pem", '-out', $withWWW,
    '-days', '1', '-subj', '/CN=a.test', '-addext', 'subjectAltName=DNS:a.test,DNS:www.a.test'
) == 0 or BAIL_OUT( 'openssl cannot make a test certificate' );
my $withoutWWW = "$dir/bare.pem";
system(
    'openssl', 'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', "$dir/key.pem", '-out', $withoutWWW,
    '-days', '1', '-subj', '/CN=a.test', '-addext', 'subjectAltName=DNS:a.test'
) == 0 or BAIL_OUT( 'openssl cannot make a test certificate' );

ok( Plugin::SGW_LetsEncrypt::_certHasName( $withWWW, 'www.a.test' ), 'a certificate for www has it' );
ok( !Plugin::SGW_LetsEncrypt::_certHasName( $withoutWWW, 'www.a.test' ), 'one without www has not' );
ok( !Plugin::SGW_LetsEncrypt::_certHasName( "$dir/none.pem", 'www.a.test' ), 'nor has no certificate at all' );

is( $plugin->_wantWWW( 0, $withoutWWW, 'www.a.test' ), 1, 'www is asked for when it resolves' );
is( $plugin->_wantWWW( 1, $withWWW, 'www.a.test' ), 0, 'and left out when it does not exist' );
is( $plugin->_wantWWW( 2, $withWWW, 'www.a.test' ), 1, 'kept when the lookup is inconclusive and the certificate has it' );
is( $plugin->_wantWWW( 2, $withoutWWW, 'www.a.test' ), 0, 'and not added on an inconclusive lookup' );

done_testing();
