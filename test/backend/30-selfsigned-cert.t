use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp;
use Test::More;
use SGWTest qw/ require_root boot plugin shadow_tables fixture_ssl_cert row /;

# The placeholder ssl_certs row is what makes i-MSCP build an SSL vhost for the
# domain at all. It must be written when missing or unusable, left alone when
# it is fine, and put back the way it was when the certificate request fails.

require_root();
boot();
shadow_tables( qw/ ssl_certs / );

my $plugin = plugin();

sub cert_row { row( 'SELECT * FROM ssl_certs WHERE domain_type = ? AND domain_id = ?', @_ ) }

sub is_valid_pair
{
    my ($row, $name) = @_;
    my $key = File::Temp->new();
    print $key $row->{'private_key'};
    close $key;
    my $cert = File::Temp->new();
    print $cert $row->{'certificate'};
    close $cert;
    my $openSSL = iMSCP::OpenSSL->new(
        private_key_container_path => $key->filename,
        certificate_container_path => $cert->filename
    );
    # iMSCP::OpenSSL validators return TRUE on success, since i-MSCP 1.5.3
    ok( $openSSL->validateCertificateChain(), $name );
}

# --- no row ------------------------------------------------------------------

is( $plugin->_updateSelfSignedCertificate( 'dmn', 101 ), 0, 'a domain with no certificate gets one' );
my $row = cert_row( 'dmn', 101 );
ok( $row, 'the ssl_certs row is written' );
is( $row->{'status'}, 'toadd', 'as a new certificate for the engine to add' );
is_valid_pair( $row, 'the placeholder key and certificate belong together' );

is( $plugin->_revertSelfSignedCertificate( 'dmn', 101 ), 0, 'reverting it succeeds' );
ok( !cert_row( 'dmn', 101 ), 'and removes the row it added' );
is( $plugin->_revertSelfSignedCertificate( 'dmn', 101 ), 0, 'reverting twice is harmless' );

# --- a usable row ---------------------------------------------------------------

is( $plugin->_updateSelfSignedCertificate( 'als', 102 ), 0, 'set up a usable certificate' );
$row = cert_row( 'als', 102 );
iMSCP::Database->factory()->getRawDb()->do( "UPDATE ssl_certs SET status = 'ok' WHERE cert_id = ?", undef, $row->{'cert_id'} );

is( $plugin->_updateSelfSignedCertificate( 'als', 102 ), 0, 'a usable certificate passes' );
my $after = cert_row( 'als', 102 );
is( $after->{'status'}, 'ok', 'without being queued for the engine again' );
is( $after->{'certificate'}, $row->{'certificate'}, 'and without being replaced' );
ok( !$plugin->{'sslCertUndo'}, 'so there is nothing to undo' );
is( $plugin->_revertSelfSignedCertificate( 'als', 102 ), 0, 'and a revert does nothing' );
ok( cert_row( 'als', 102 ), 'the usable certificate survives the revert' );

# --- an unusable row --------------------------------------------------------------

fixture_ssl_cert( 'sub', 103, status => 'ok' );
is( $plugin->_updateSelfSignedCertificate( 'sub', 103 ), 0, 'an empty certificate is replaced' );
$row = cert_row( 'sub', 103 );
is( $row->{'status'}, 'tochange', 'and queued as a change' );
is_valid_pair( $row, 'with a key and certificate that belong together' );

is( $plugin->_revertSelfSignedCertificate( 'sub', 103 ), 0, 'reverting the change succeeds' );
$row = cert_row( 'sub', 103 );
is_deeply(
    [ @{$row}{qw/ status private_key certificate /} ], [ 'ok', '', '' ],
    'and restores the row as it was'
);

fixture_ssl_cert( 'dmn', 104, private_key => 'not a key', certificate => 'not a certificate', status => 'ok' );
is( $plugin->_updateSelfSignedCertificate( 'dmn', 104 ), 0, 'a garbage certificate is replaced' );
is_valid_pair( cert_row( 'dmn', 104 ), 'with a usable one' );

done_testing();
