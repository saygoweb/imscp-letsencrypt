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


# --- _certNames -------------------------------------------------------------------

is_deeply( [ sort( Plugin::SGW_LetsEncrypt::_certNames( $withWWW ) ) ], [ 'a.test', 'www.a.test' ],
    'the names of a certificate are its subjectAltName' );
is_deeply( [ Plugin::SGW_LetsEncrypt::_certNames( "$dir/none.pem" ) ], [], 'no certificate has no names' );

# --- _certIsCurrent (#47) -----------------------------------------------------------
# A certificate certbot holds, for exactly the names wanted and not due for renewal,
# is used without asking certbot.

my $live = "$dir/live";
mkdir $live or die $!;
sub make_cert
{
    my ($days, @names) = @_;
    system(
        'openssl', 'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', "$dir/key.pem",
        '-out', "$live/cert.pem", '-days', $days, '-subj', "/CN=$names[0]",
        '-addext', 'subjectAltName=' . join( ',', map { "DNS:$_" } @names )
    ) == 0 or BAIL_OUT( 'openssl cannot make a test certificate' );
}
{
    no warnings 'redefine';
    my $hasConf = 1;
    local *Plugin::SGW_LetsEncrypt::_lineagePaths = sub { { live => $live } };
    local *Plugin::SGW_LetsEncrypt::_hasRenewalConf = sub { $hasConf };

    make_cert( 90, 'a.test' );
    ok( $plugin->_certIsCurrent( 'a.test', 0 ), 'a certificate for the name, valid for 90 days, is current' );
    ok( !$plugin->_certIsCurrent( 'a.test', 1 ), 'but not when www is to be added to it' );
    ok( !$plugin->_certIsCurrent( 'b.test', 0 ), 'nor for another name' );
    $hasConf = 0;
    ok( !$plugin->_certIsCurrent( 'a.test', 0 ), 'nor when certbot has no renewal config for it' );
    $hasConf = 1;

    make_cert( 90, 'a.test', 'www.a.test' );
    ok( $plugin->_certIsCurrent( 'a.test', 1 ), 'one with www is current when www is wanted' );
    ok( !$plugin->_certIsCurrent( 'a.test', 0 ), 'but not when www is to be taken off' );

    make_cert( 10, 'a.test' );
    ok( !$plugin->_certIsCurrent( 'a.test', 0 ), 'one due for renewal is not current' );

    unlink "$live/cert.pem";
    ok( !$plugin->_certIsCurrent( 'a.test', 0 ), 'and no certificate is not current' );
}

# --- _hostAddresses -----------------------------------------------------------------

is_deeply(
    [ Plugin::SGW_LetsEncrypt::_hostAddresses(
        "a.test has address 192.0.2.1\na.test has IPv6 address 2001:db8::1\na.test mail is handled by 10 mx.a.test.\n"
    ) ],
    [ 0, '192.0.2.1', '2001:db8::1' ],
    'host output gives the IPv4 and IPv6 addresses of a name'
);
is_deeply(
    [ Plugin::SGW_LetsEncrypt::_hostAddresses(
        "www.a.test is an alias for a.test.\na.test has address 192.0.2.1\n"
    ) ],
    [ 0, '192.0.2.1' ],
    'and follows an alias'
);
is_deeply( [ Plugin::SGW_LetsEncrypt::_hostAddresses( "Host nope.test not found: 3(NXDOMAIN)\n" ) ], [ 1 ],
    'a name that does not exist' );
is_deeply( [ Plugin::SGW_LetsEncrypt::_hostAddresses( ";; connection timed out; no servers could be reached\n" ) ],
    [ 2 ], 'a lookup that failed is unclear' );
is_deeply( [ Plugin::SGW_LetsEncrypt::_hostAddresses( undef ) ], [ 2 ], 'and so is no output at all' );

# --- _foreignAddresses ----------------------------------------------------------------

is_deeply( [ Plugin::SGW_LetsEncrypt::_foreignAddresses( [ '192.0.2.1' ], [ '192.0.2.1' ] ) ], [],
    'an address of this server is not foreign' );
is_deeply( [ Plugin::SGW_LetsEncrypt::_foreignAddresses( [ '2001:DB8:0::1' ], [ '2001:db8::1' ] ) ], [],
    'nor is one spelt differently' );
is_deeply( [ Plugin::SGW_LetsEncrypt::_foreignAddresses( [ '192.0.2.1', '198.51.100.7' ], [ '192.0.2.1' ] ) ],
    [ '198.51.100.7' ], 'any other address is' );

# --- _checkPointsHere / _wwwPointsElsewhere (#45) ----------------------------------------

{
    no warnings qw/ redefine once /;
    my %dns;
    local *Plugin::SGW_LetsEncrypt::_resolve = sub { @{ $dns{$_[1]} // [ 1 ] } };
    local *Plugin::SGW_LetsEncrypt::_serverAddresses = sub { ( '10.0.0.5', '192.0.2.1' ) };
    local $main::imscpConfig{'BASE_SERVER_PUBLIC_IP'} = '192.0.2.1';

    %dns = ( 'a.test' => [ 0, '192.0.2.1' ], 'www.a.test' => [ 0, '198.51.100.7' ] );
    is( $plugin->_checkPointsHere( 'a.test' ), 0, 'a name that points here can be asked for' );
    is( $plugin->_wwwPointsElsewhere( 'a.test' ), 1, 'a www name pointing at another server is noticed' );

    $dns{'a.test'} = [ 0, '198.51.100.7' ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'a name that points elsewhere cannot' );
    like( $plugin->_lastError(), qr/^a\.test resolves to 198\.51\.100\.7, which is not this server \(192\.0\.2\.1\)\./,
        'saying where it points and where it should' );

    $dns{'a.test'} = [ 0, '192.0.2.1', '2001:db8::99' ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'nor can one with any address elsewhere, IPv6 included' );
    like( $plugin->_lastError(), qr/resolves to 2001:db8::99,/, 'naming only the address that is not here' );

    $dns{'a.test'} = [ 1 ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'a name that does not exist cannot' );
    like( $plugin->_lastError(), qr/^Cannot resolve a\.test: it does not exist/, 'saying so' );

    $dns{'a.test'} = [ 2 ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'nor one the public DNS gives no address for' );
    like( $plugin->_lastError(), qr/^Cannot resolve a\.test: the public DNS gave no address/, 'saying so' );

    $dns{'www.a.test'} = [ 2 ];
    is( $plugin->_wwwPointsElsewhere( 'a.test' ), 0, 'an unclear www lookup is not taken as pointing elsewhere' );

    local $plugin->{'config'} = { check_dns_points_here => 0 };
    $dns{'a.test'} = [ 0, '198.51.100.7' ];
    $dns{'www.a.test'} = [ 0, '198.51.100.7' ];
    is( $plugin->_checkPointsHere( 'a.test' ), 0, 'with the check turned off, a name pointing elsewhere can be asked for' );
    is( $plugin->_wwwPointsElsewhere( 'a.test' ), 0, 'and www is not checked' );
    $dns{'a.test'} = [ 1 ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'but it must still exist' );
}

is( $plugin->_checkDNSEnabled(), 1, 'the check is on by default' );

done_testing();
