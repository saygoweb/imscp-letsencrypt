use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
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

done_testing();
