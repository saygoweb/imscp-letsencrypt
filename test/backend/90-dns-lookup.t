use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use SGWTest qw/ require_root load_plugin /;

# _lookup decides whether certbot is asked for a certificate at all, and whether
# the www. name goes on it too. It asks a public resolver, so it only runs when
# the network is wanted: SGW_NETWORK_TESTS=1.

plan skip_all => 'set SGW_NETWORK_TESTS=1 to query the public DNS' unless $ENV{'SGW_NETWORK_TESTS'};
require_root();
load_plugin() or BAIL_OUT( 'cannot load the plugin' );

# Names reserved for exactly this by RFC 2606 / RFC 6761, so the answers do not drift.
is( Plugin::SGW_LetsEncrypt::_lookup( 'example.com' ), 0, 'a name with an address resolves' );
is( Plugin::SGW_LetsEncrypt::_lookup( 'www.example.com' ), 0, 'so does its www name' );
is( Plugin::SGW_LetsEncrypt::_lookup( "nothing-$$.example.invalid" ), 1, 'a name that does not exist is reported as missing' );
is( Plugin::SGW_LetsEncrypt::_lookup( 'nodots' ), 1, 'a single-label name that does not exist is reported as missing' );


my $plugin = bless {}, 'Plugin::SGW_LetsEncrypt';
my ($status, @addresses) = $plugin->_resolve( 'example.com' );
is( $status, 0, '_resolve finds a name with an address' );
ok( scalar( grep { /^[0-9.]+$/ } @addresses ), 'and gives its IPv4 addresses' );
is( ( $plugin->_resolve( "nothing-$$.example.invalid" ) )[0], 1, 'and reports a name that does not exist' );

done_testing();
