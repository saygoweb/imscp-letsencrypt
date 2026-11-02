use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use SGWTest qw/
    require_root boot plugin shadow_tables create_letsencrypt_table fixture_domain fixture_letsencrypt
    row test_name cleanup_path cleanup_dir
/;

# A certificate's lineage under /etc/letsencrypt - live/<name>, archive/<name>
# and renewal/<name>.conf - must survive its domain being disabled and enabled
# again (#42), go entirely when the certificate is deleted (#40), and a lineage
# an earlier version of the plugin left orphaned must not stop a new
# certificate being issued. certbot is the mock in backend/, which keeps
# lineages the way certbot 5 does.

require_root();
boot();
shadow_tables( qw/ ssl_certs domain domain_aliasses subdomain / );
create_letsencrypt_table();

my $plugin = plugin();
my $LE = '/etc/letsencrypt';
cleanup_dir( $_ ) for map { "$LE$_" } '', qw{ /live /archive /renewal /renewal-disabled /orphaned };

# Every name this test makes up carries its pid, so this takes away all it left
# behind, a <name>-0001 lineage or a lineage moved aside included.
END {
    cleanup_path( glob "/etc/letsencrypt/{live,archive,renewal,renewal-disabled,orphaned}/*-$$.*" );
}

sub le_row { row( 'SELECT * FROM letsencrypt WHERE letsencrypt_id = ?', @_ ) }

# Queue a certificate for a new domain
sub queue
{
    my ($label, %f) = @_;
    my $name = $f{'cert_name'} // test_name( $label );
    my $id = fixture_domain( 'dmn', $name );
    my $leId = fixture_letsencrypt( type => 'dmn', id => $id, cert_name => $name, status => 'toadd' );
    ($id, $leId, $name);
}

sub requeue
{
    my ($leId, $status) = @_;
    iMSCP::Database->factory()->getRawDb()->do(
        'UPDATE letsencrypt SET status = ? WHERE letsencrypt_id = ?', undef, $status, $leId
    );
}

# The lineages certbot holds for a name: the name itself and any <name>-NNNN beside it
sub lineages
{
    my ($name) = @_;
    sort map { s{^.*/}{}r } grep { -d } ("$LE/live/$name", glob "$LE/live/$name-[0-9][0-9][0-9][0-9]");
}

sub slurp
{
    my ($file) = @_;
    open my $fh, '<', $file or return undef;
    local $/;
    <$fh>;
}

sub has_config
{
    my $content = slurp( $_[0] );
    defined $content && $content =~ /\S/;
}

# Build a vhost for the domain, the way the engine calls the listener
sub build
{
    my ($tpl, $name) = @_;
    my $cfg = "    SSLEngine On\n    SSLCertificateFile x\n";
    $plugin->_onAfterHttpdBuildConf( \$cfg, $tpl, { DOMAIN_NAME => $name } );
}

sub issued
{
    my ($leId, $what) = @_;
    my $le = le_row( $leId );
    is( $le->{'status'}, 'ok', $what ) or diag( "state: $le->{'state'}" );
}

# --- disable, then enable again (#42) ---------------------------------------------

my ($id, $le, $name) = queue( 'cycle' );
is( $plugin->run(), 0, 'a certificate is requested' );
issued( $le, 'and issued' );
my $conf = slurp( "$LE/renewal/$name.conf" );
my $cert = slurp( "$LE/live/$name/cert.pem" );
ok( has_config( "$LE/renewal/$name.conf" ), 'certbot renews it' );

is( build( 'domain_disabled.tpl', $name ), 0, 'the domain is disabled' );
ok( !-e "$LE/renewal/$name.conf", 'certbot no longer renews it' );
is( slurp( "$LE/renewal-disabled/$name.conf" ), $conf, 'its renewal config is kept aside' );
is( slurp( "$LE/live/$name/cert.pem" ), $cert, 'and its certificate kept' );

# Enabled, the domain is rebuilt before the panel's request is processed
is( build( 'domain.tpl', $name ), 0, 'the domain is enabled again' );
is( slurp( "$LE/renewal/$name.conf" ), $conf, 'its renewal config is back' );
ok( !-e "$LE/renewal-disabled/$name.conf", 'and no longer kept aside' );

# Or the request is processed before the domain is rebuilt
build( 'domain_disabled.tpl', $name );
requeue( $le, 'tochange' );
is( $plugin->run(), 0, 'the certificate of a re-enabled domain is requested again' );
issued( $le, 'and succeeds' );
is( slurp( "$LE/live/$name/cert.pem" ), $cert, 'keeping the certificate it had' );
is_deeply( [ lineages( $name ) ], [ $name ], 'in its one lineage' );
is( slurp( "$LE/renewal/$name.conf" ), $conf, 'which certbot renews' );
ok( !-e "$LE/renewal-disabled/$name.conf", 'with nothing left aside' );

# --- delete, then request the same name again (#40) --------------------------------

($id, $le, $name) = queue( 'readd' );
$plugin->run();
requeue( $le, 'todelete' );
is( $plugin->run(), 0, 'a certificate is deleted' );
ok( !le_row( $le ), 'its row goes' );
ok( !-e "$LE/$_", "$_ goes" ) for "live/$name", "archive/$name", "renewal/$name.conf";

my $again = fixture_letsencrypt( type => 'dmn', id => $id, cert_name => $name, status => 'toadd' );
is( $plugin->run(), 0, 'the same name is requested again' );
issued( $again, 'and issued' );
is_deeply( [ lineages( $name ) ], [ $name ], 'into the lineage the vhost points at, with no -0001 beside it' );
ok( has_config( "$LE/renewal/$name.conf" ), 'which certbot renews' );

# --- delete while disabled --------------------------------------------------------

($id, $le, $name) = queue( 'deldisabled' );
$plugin->run();
build( 'domain_disabled.tpl', $name );
requeue( $le, 'todelete' );
is( $plugin->run(), 0, "a disabled domain's certificate is deleted" );
ok( !le_row( $le ), 'its row goes' );
ok( !-e "$LE/$_", "$_ goes" ) for "live/$name", "archive/$name", "renewal/$name.conf", "renewal-disabled/$name.conf";

# --- delete a lineage certbot no longer knows about -------------------------------

($id, $le, $name) = queue( 'delorphan' );
$plugin->run();
unlink "$LE/renewal/$name.conf";
requeue( $le, 'todelete' );
is( $plugin->run(), 0, 'a certificate with no renewal config is deleted' );
ok( !le_row( $le ), 'its row goes' );
ok( !-e "$LE/$_", "$_ goes" ) for "live/$name", "archive/$name";

done_testing();
