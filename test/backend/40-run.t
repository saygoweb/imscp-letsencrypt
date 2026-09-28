use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw/ make_path /;
use Test::More;
use SGWTest qw/
    require_root boot plugin shadow_tables create_letsencrypt_table fixture_domain fixture_letsencrypt
    fixture_ssl_cert row rows test_name cleanup_path cleanup_dir
/;

# run() is what the engine calls: it picks up the rows the panel queued and
# takes each through certbot. certbot is the mock in backend/, which issues a
# self-signed certificate and fails for any name under .fail.local.

require_root();
boot();
shadow_tables( qw/ ssl_certs domain domain_aliasses subdomain / );
create_letsencrypt_table();

my $plugin = plugin();
cleanup_dir( $_ ) for qw{ /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/renewal };
my $guiCerts = do { no warnings 'once'; $main::imscpConfig{'GUI_ROOT_DIR'} } . '/data/certs';

sub le_row { row( 'SELECT * FROM letsencrypt WHERE letsencrypt_id = ?', @_ ) }
sub cert_row { row( 'SELECT * FROM ssl_certs WHERE domain_type = ? AND domain_id = ?', @_ ) }

# Queue a certificate for a new domain of the given type
sub queue
{
    my ($type, $label, %f) = @_;
    my $name = $f{'cert_name'} // test_name( $label );
    cleanup_path( "/etc/letsencrypt/live/$name" );
    my $id = fixture_domain( $type, $name );
    my $leId = fixture_letsencrypt( type => $type, id => $id, cert_name => $name, %f );
    ($id, $leId, $name);
}

# --- add ---------------------------------------------------------------------

my ($dmnId, $dmnLe, $dmnName) = queue( 'dmn', 'dmn', http_forward => 1 );
my ($alsId, $alsLe, $alsName) = queue( 'als', 'als' );
my ($subId, $subLe, $subName) = queue( 'sub', 'sub' );
my ($failId, $failLe, $failName) = queue( 'dmn', 'fail', cert_name => "fail-$$.fail.local" );
my ($okId, $okLe) = queue( 'dmn', 'done', status => 'ok' );

is( $plugin->run(), 0, 'run succeeds even though one domain fails' );

for ([ 'domain', $dmnLe, $dmnName ], [ 'alias', $alsLe, $alsName ], [ 'subdomain', $subLe, $subName ]) {
    my ($what, $leId, $name) = @{$_};
    my $le = le_row( $leId );
    is( $le->{'status'}, 'ok', "the $what is ok" ) or diag( "state: $le->{'state'}" );
    is( $le->{'state'}, '', "with no error recorded against the $what" );
    ok( -f "/etc/letsencrypt/live/$name/$_", "the $what has $_" ) for qw/ privkey.pem cert.pem chain.pem /;
}

my $cert = cert_row( 'dmn', $dmnId );
ok( $cert, 'the domain has an ssl_certs row' );
is( $cert->{'allow_hsts'}, 'on', 'http is forwarded to https when asked for' );
is( row( 'SELECT domain_status FROM domain WHERE domain_id = ?', $dmnId )->{'domain_status'}, 'toadd',
    'the domain is queued for a rebuild' );

$cert = cert_row( 'als', $alsId );
ok( $cert, 'the alias has an ssl_certs row of its own' );
is( $cert->{'allow_hsts'}, 'off', 'and is not forwarded when not asked for' );
is( row( 'SELECT alias_status FROM domain_aliasses WHERE alias_id = ?', $alsId )->{'alias_status'}, 'toadd',
    'the alias is queued for a rebuild' );

ok( cert_row( 'sub', $subId ), 'the subdomain has an ssl_certs row of its own' );
is( row( 'SELECT subdomain_status FROM subdomain WHERE subdomain_id = ?', $subId )->{'subdomain_status'}, 'toadd',
    'the subdomain is queued for a rebuild' );

ok( !cert_row( 'dmn', $dmnId + 1000 ), 'no row lands against an id nobody asked for' );

# --- a failed request ------------------------------------------------------------

my $fail = le_row( $failLe );
is( $fail->{'status'}, 'error', 'a certbot failure is reported against its domain' );
like( $fail->{'state'}, qr/^certbot failed for \Q$failName\E: /, 'saying certbot failed' );
like( $fail->{'state'}, qr/NXDOMAIN/, 'and why' );
unlike( $fail->{'state'}, qr/\n/, 'on one line' );
ok( !cert_row( 'dmn', $failId ), 'the placeholder certificate is taken back' );
is( row( 'SELECT domain_status FROM domain WHERE domain_id = ?', $failId )->{'domain_status'}, 'ok',
    'and the domain is not rebuilt' );

is( le_row( $okLe )->{'status'}, 'ok', 'a row with nothing to do is left alone' );
ok( !cert_row( 'dmn', $okId ), 'and given no certificate' );

# --- change ----------------------------------------------------------------------

my $dbh = iMSCP::Database->factory()->getRawDb();
$dbh->do( "UPDATE letsencrypt SET status = 'tochange', http_forward = 0 WHERE letsencrypt_id = ?", undef, $dmnLe );
$dbh->do( "UPDATE ssl_certs SET status = 'ok' WHERE domain_type = 'dmn' AND domain_id = ?", undef, $dmnId );
is( $plugin->run(), 0, 'a change runs' );
is( le_row( $dmnLe )->{'status'}, 'ok', 'the changed domain is ok' );
is( cert_row( 'dmn', $dmnId )->{'allow_hsts'}, 'off', 'and no longer forwarded' );
is( scalar( () = rows( "SELECT cert_id FROM ssl_certs WHERE domain_type = 'dmn' AND domain_id = ?", $dmnId ) ), 1,
    'still with a single ssl_certs row' );

# A retry of the failed domain fails the same way, and does not wipe out the
# error with an empty one.
$dbh->do( "UPDATE letsencrypt SET status = 'tochange' WHERE letsencrypt_id = ?", undef, $failLe );
$plugin->run();
like( le_row( $failLe )->{'state'}, qr/NXDOMAIN/, 'a retried failure is reported again' );

# --- delete ----------------------------------------------------------------------

# A host that has never run certbot has no /etc/letsencrypt at all; the
# cleanup_dir calls above take away whatever this creates.
make_path( '/etc/letsencrypt/renewal' );
my $renewal = cleanup_path( "/etc/letsencrypt/renewal/$alsName.conf" );
my $guiCert = cleanup_path( "$guiCerts/$alsName.pem" );
for my $file ($renewal, $guiCert) {
    open my $fh, '>', $file or die "cannot write $file: $!";
    close $fh;
}
$dbh->do( "UPDATE domain_aliasses SET alias_status = 'ok' WHERE alias_id = ?", undef, $alsId );
$dbh->do( "UPDATE letsencrypt SET status = 'todelete' WHERE letsencrypt_id = ?", undef, $alsLe );

is( $plugin->run(), 0, 'a delete runs' );
ok( !le_row( $alsLe ), 'the letsencrypt row is gone' );
ok( !cert_row( 'als', $alsId ), 'the ssl_certs row is gone' );
ok( !-e $renewal, 'certbot no longer renews it' );
ok( !-e $guiCert, 'the certificate file i-MSCP kept is gone' );
is( row( 'SELECT alias_status FROM domain_aliasses WHERE alias_id = ?', $alsId )->{'alias_status'}, 'toadd',
    'the alias is queued for a rebuild without SSL' );
ok( cert_row( 'dmn', $dmnId ), "another domain's certificate is untouched" );

# --- nothing to do ---------------------------------------------------------------

my @before = rows( 'SELECT * FROM letsencrypt ORDER BY letsencrypt_id' );
is( $plugin->run(), 0, 'a run with nothing queued succeeds' );
is_deeply( [ rows( 'SELECT * FROM letsencrypt ORDER BY letsencrypt_id' ) ], \@before, 'and changes nothing' );

done_testing();
