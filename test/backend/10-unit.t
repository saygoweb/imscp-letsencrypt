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

$plugin->_error( 'The site is down.', "certbot said:\n  line 1\n  line 2\n" );
is( $plugin->_lastError(), 'The site is down.', 'the detail is not part of the message the client sees' );
like( $plugin->{'lastErrorDetail'}, qr/line 1\n  line 2/, 'but is kept, as it is, for the log' );
like( scalar Plugin::SGW_LetsEncrypt::getMessageByType( 'error' ), qr/The site is down\.\ncertbot said:/,
    'which has both' );
$plugin->_error( 'Again.' );
ok( !defined $plugin->{'lastErrorDetail'}, 'a later error without detail does not carry the earlier one' );

$plugin->_clearError();
ok( !defined $plugin->{'lastError'}, "_clearError forgets the previous domain's error" );
ok( !defined $plugin->{'lastErrorDetail'}, 'and its detail' );

# --- _certbotError (#46) ------------------------------------------------------
# The message is what the client reads - in the panel, and through GraphQL in
# apps that never name the certificate authority - so it says what is wrong and
# what to do. certbot's own output goes to the detail, for the log.

sub certbot_error { [ Plugin::SGW_LetsEncrypt::_certbotError( 'a.test', 1, undef, $_[0] ) ] }

# certbot 2+ reports a failed challenge like this
sub challenge
{
    my ($domain, $type, $detail) = @_;
    "Certbot failed to authenticate some domains (authenticator: apache). The Certificate Authority reported "
        . "these problems:\n  Domain: $domain\n  Type:   $type\n  Detail: $detail\n\nHint: The Certificate "
        . "Authority failed to verify the temporary Apache configuration changes made by Certbot.\n";
}

my ($message, $detail) = @{ certbot_error( challenge( 'a.test', 'dns', 'DNS problem: NXDOMAIN looking up A for a.test' ) ) };
like( $message, qr/^a\.test cannot be found in the public DNS\. /, 'a name missing from the DNS' );
like( $detail, qr/^certbot failed for a\.test: Certbot failed .*NXDOMAIN/s, 'with what certbot said as the detail' );

($message) = @{ certbot_error( challenge(
    'www.a.test', 'connection', '192.0.2.1: Fetching http://www.a.test/.well-known/acme-challenge/x: Timeout during '
    . 'connect (likely firewall problem)'
) ) };
like( $message, qr/^www\.a\.test could not be reached on port 80 \(http\)\. /,
    'a site that cannot be reached, naming the name that failed' );

($message) = @{ certbot_error( challenge(
    'a.test', 'unauthorized', '192.0.2.1: Invalid response from http://a.test/.well-known/acme-challenge/x: 404'
) ) };
like( $message, qr{^A check request to http://a\.test/\.well-known/acme-challenge/ did not reach this site\. },
    'a challenge answered by something else' );

($message) = @{ certbot_error( challenge( 'a.test', 'caa', 'CAA record for a.test prevents issuance' ) ) };
like( $message, qr/^a\.test has a CAA record in its DNS /, 'a CAA record in the way' );

($message) = @{ certbot_error(
    "An unexpected error occurred:\nError creating new order :: too many certificates (5) already issued for this "
    . "exact set of identifiers in the last 168h0m0s, retry after 2026-11-04 10:15:00 UTC: see "
    . "https://letsencrypt.org/docs/rate-limits/#new-certificates-per-exact-set-of-identifiers\n"
) };
is( $message, 'Too many certificate requests for a.test have been made recently. Try again after 2026-11-04 10:15:00 UTC.',
    'a rate limit, saying when to try again' );
($message) = @{ certbot_error( "Error: too many failed authorizations recently\n" ) };
like( $message, qr/Try again in an hour or so\.$/, 'or roughly, when certbot does not say' );

($message) = @{ certbot_error( "Error while running apache2ctl configtest.\nAH00526: Syntax error on line 3\n" ) };
like( $message, qr/^The certificate for a\.test could not be issued because of a problem on this server\. Contact support\.$/,
    'a problem on the server' );

($message, $detail) = @{ certbot_error( "Something nobody has seen before\n" ) };
like( $message, qr/^The certificate for a\.test could not be issued\. Try again later/, 'anything else' );
like( $detail, qr/Something nobody has seen before/, 'with what certbot said as the detail' );

for my $case (
    challenge( 'a.test', 'dns', 'DNS problem: NXDOMAIN looking up A for a.test' ),
    "Error: too many failed authorizations recently\n",
    "Something nobody has seen before\n"
) {
    unlike( certbot_error( $case )->[0], qr/certbot|Let.s Encrypt|Certificate Authority|acme-v02/i,
        'the message names neither certbot nor the certificate authority' );
}

is_deeply(
    [ Plugin::SGW_LetsEncrypt::_certbotError( 'a.test', 1, 'out', '  ' ) ]->[1], 'certbot failed for a.test: out',
    'stdout is used when stderr is blank'
);
is(
    [ Plugin::SGW_LetsEncrypt::_certbotError( 'a.test', 3, undef, undef ) ]->[1],
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
unlike( $cmd, qr/www\./, 'alone when its www name does not resolve' );
like( $plugin->_certbotCommand( 'a.test', 1 ), qr/ --expand -d '?www\.a\.test'?$/, 'and with its www name when it does' );

# The challenge is answered from the webroot, which the plugin's Apache conf
# serves on every vhost. certbot's Apache plugin parsed the whole Apache config
# for each certificate - minutes of CPU on a server with hundreds of vhosts -
# and reloaded Apache several times over.
$plugin->{'webroot'} = '/srv/le-webroot';
$cmd = $plugin->_certbotCommand( 'a.test', 1 );
like( $cmd, qr/ certonly --webroot -w '?\/srv\/le-webroot'? /, 'with the webroot authenticator, from the webroot' );
unlike( $cmd, qr/--apache|--installer|(?:^| )-i /, "and neither certbot's Apache plugin nor any installer" );
like( $cmd, qr/ -w \S+ .*-d '?a\.test'?/, 'the webroot coming before the names it is for' );
delete $plugin->{'webroot'};
like( $plugin->_certbotCommand( 'a.test', 0 ), qr/ -w '?\/var\/www\/sgw-letsencrypt'? /,
    'the webroot is /var/www/sgw-letsencrypt unless told otherwise' );

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
    like( $plugin->_lastError(), qr/^a\.test points at 198\.51\.100\.7, not at this server \(192\.0\.2\.1\)\./,
        'saying where it points and where it should' );
    unlike( $plugin->_lastError(), qr/Let.s Encrypt|certbot/i, 'without naming the certificate authority' );

    $dns{'a.test'} = [ 0, '192.0.2.1', '2001:db8::99' ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'nor can one with any address elsewhere, IPv6 included' );
    like( $plugin->_lastError(), qr/points at 2001:db8::99,/, 'naming only the address that is not here' );

    $dns{'a.test'} = [ 1 ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'a name that does not exist cannot' );
    like( $plugin->_lastError(), qr/^a\.test cannot be found in the public DNS\./, 'saying so' );

    $dns{'a.test'} = [ 2 ];
    is( $plugin->_checkPointsHere( 'a.test' ), 1, 'nor one the public DNS gives no address for' );
    like( $plugin->_lastError(), qr/^a\.test could not be looked up in the public DNS: /, 'saying so' );

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
