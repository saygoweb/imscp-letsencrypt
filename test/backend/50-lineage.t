use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp;
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

# --- a lineage an earlier plugin left orphaned -----------------------------------
# Up to 2.1.4 disabling or deleting removed only the renewal config, and a failed
# certbot 5.9 run leaves an empty one. Servers have such lineages today, mostly
# for sites that are up and serving the certificate from live/<name>: certbot
# --apache runs apache2ctl configtest first, so live/<name> must stay where it is.

my $vhosts = File::Temp->newdir();
local $ENV{'CERTBOT_MOCK_APACHE_CONF_DIR'} = $vhosts->dirname;

# The site's SSL vhost, as the listener rewrites it
sub vhost
{
    my ($name) = @_;
    my $conf = "$vhosts/${name}_ssl.conf";
    open my $fh, '>', $conf or die "cannot write $conf: $!";
    print $fh (
        "<VirtualHost *:443>\n",
        "    SSLEngine On\n",
        "    SSLCertificateFile $LE/live/$name/cert.pem\n",
        "    SSLCertificateKeyFile $LE/live/$name/privkey.pem\n",
        "    SSLCertificateChainFile $LE/live/$name/chain.pem\n",
        "</VirtualHost>\n"
    );
    close $fh;
    $conf;
}

# Another lineage certbot does know, whose account the rebuilt config is to use
my $sibling = "$LE/renewal/sibling-$$.sgw-le.test.conf";
open my $sfh, '>', $sibling or die "cannot write $sibling: $!";
print $sfh "cert = /etc/hostname\n\n[renewalparams]\naccount = mockaccount$$\nauthenticator = apache\n"
    . "server = https://acme-staging-v02.api.letsencrypt.org/directory\n";
close $sfh;

for my $case (
    [ 'orphan', 'no renewal config', undef ],
    [ 'emptyconf', 'an empty renewal config', '' ],
    [ 'junkconf', 'a renewal config certbot cannot load', "# junk\n" ]
) {
    my ($label, $what, $content) = @{$case};
    ($id, $le, $name) = queue( $label );
    $plugin->run();
    my $old = slurp( "$LE/live/$name/cert.pem" );
    unlink "$LE/renewal/$name.conf";
    if (defined $content) {
        open my $fh, '>', "$LE/renewal/$name.conf" or die $!;
        print $fh $content;
        close $fh;
    }
    my $site = vhost( $name );
    requeue( $le, 'tochange' );

    is( $plugin->run(), 0, "the certificate of a site with $what is requested again" );
    issued( $le, 'and succeeds' );
    is( slurp( "$LE/live/$name/cert.pem" ), $old, 'keeping the certificate the site serves' );
    is_deeply( [ lineages( $name ) ], [ $name ], 'in its one lineage' );
    my $conf = slurp( "$LE/renewal/$name.conf" ) // '';
    like( $conf, qr{^cert = \Q$LE/live/$name/cert.pem\E$}m, 'which certbot renews again' );
    like( $conf, qr{^archive_dir = \Q$LE/archive/$name\E$}m, 'from its archive' );
    my $account = "mockaccount$$";
    like( $conf, qr{^account = \Q$account\E$}m, 'with the account the other lineages use' );
    like( $conf, qr{^server = https://acme-staging-v02\.api\.letsencrypt\.org/directory$}m, 'and their server' );
    like( $conf, qr{^authenticator = apache$}m, 'through apache' );
    like( $conf, qr{^key_type = rsa$}m, 'for the key it has' );
    is( scalar( () = glob "$LE/orphaned/$name-*" ), 0, 'with nothing moved aside' );
    unlink $site;
}
unlink $sibling;

# A lineage whose live/ is not certbot's - plain files, not links into archive/ -
# cannot be adopted. With no site using it, it is moved aside for a new one.
($id, $le, $name) = queue( 'unadoptable' );
$plugin->run();
unlink "$LE/renewal/$name.conf";
for my $file (qw/ privkey cert chain fullchain /) {
    my $link = "$LE/live/$name/$file.pem";
    my $content = slurp( $link );
    unlink $link;
    open my $fh, '>', $link or die $!;
    print $fh $content;
    close $fh;
}
my $old = slurp( "$LE/live/$name/cert.pem" );
requeue( $le, 'tochange' );
is( $plugin->run(), 0, 'a lineage that cannot be adopted is requested again' );
issued( $le, 'and issued' );
is_deeply( [ lineages( $name ) ], [ $name ], 'into the lineage the vhost points at' );
ok( has_config( "$LE/renewal/$name.conf" ), 'which certbot renews' );
isnt( slurp( "$LE/live/$name/cert.pem" ), $old, 'with a new certificate' );
my @aside = glob "$LE/orphaned/$name-*";
is( scalar @aside, 1, 'the old lineage is kept aside' );
is( slurp( "$aside[0]/live/$name/cert.pem" ), $old, 'with its certificate still readable' );

# --- certbot saving the certificate somewhere else is a failure ------------------
# Should certbot reject a renewal config the plugin found fine, it saves the
# certificate as an unused <name>-0001 while the vhost keeps serving the old one.

($id, $le, $name) = queue( 'elsewhere' );
$plugin->run();
requeue( $le, 'tochange' );
{
    local $ENV{'CERTBOT_MOCK_NEW_LINEAGE'} = 1;
    is( $plugin->run(), 0, 'a request certbot saves under another name runs' );
}
my $elsewhere = le_row( $le );
is( $elsewhere->{'status'}, 'error', 'and is reported as failed' );
like( $elsewhere->{'state'}, qr/\Q$name\E-0001/, 'naming where certbot put it' );

# --- a request for a domain that is still disabled -------------------------------
# Disabling stops renewals, and nothing must start them again, or bring the site
# back, until the domain is enabled.

($id, $le, $name) = queue( 'stilldisabled' );
$plugin->run();
build( 'domain_disabled.tpl', $name );
my $dbh = iMSCP::Database->factory()->getRawDb();
$dbh->do( "UPDATE domain SET domain_status = 'disabled' WHERE domain_id = ?", undef, $id );
requeue( $le, 'tochange' );
is( $plugin->run(), 0, 'a request for a disabled domain runs' );
ok( !-e "$LE/renewal/$name.conf", 'certbot still does not renew it' );
ok( -f "$LE/renewal-disabled/$name.conf", 'its renewal config stays aside' );
is( row( 'SELECT domain_status FROM domain WHERE domain_id = ?', $id )->{'domain_status'}, 'disabled',
    'and the domain stays disabled' );
isnt( le_row( $le )->{'status'}, 'tochange', 'the request is not left queued' );

# --- a delete that cannot rebuild the domain keeps the lineage --------------------
# The vhost points at live/<name> until the domain is rebuilt without SSL; with
# no rebuild coming, removing the files would leave httpd a vhost it cannot load.

$name = test_name( 'norebuild' );
system( $plugin->{'certbotTest'}, 'certonly', '--cert-name', $name, '-d', $name ) == 0 or die 'mock certbot failed';
$le = fixture_letsencrypt( type => 'dmn', id => 0, cert_name => $name, status => 'todelete' );
is( $plugin->run(), 0, 'a delete for a domain that cannot be rebuilt runs' );
is( le_row( $le )->{'status'}, 'error', 'and fails' );
ok( -f "$LE/live/$name/cert.pem", 'leaving the certificate the vhost uses' );

# --- a failed request puts an orphaned lineage back --------------------------------

my $failName = "orphanfail-$$.fail.local";
($id, $le, $name) = queue( 'orphanfail', cert_name => $failName );
mkdir "$LE/archive";
mkdir "$LE/archive/$failName" or die $!;
mkdir "$LE/live/$failName" or die $!;
open my $ofh, '>', "$LE/archive/$failName/cert1.pem" or die $!;
print $ofh "old\n";
close $ofh;
symlink "../../archive/$failName/cert1.pem", "$LE/live/$failName/cert.pem" or die $!;

is( $plugin->run(), 0, 'a request for an orphaned lineage that certbot refuses runs' );
is( le_row( $le )->{'status'}, 'error', 'and fails' );
is( slurp( "$LE/live/$failName/cert.pem" ), "old\n", 'leaving the old certificate where the vhost expects it' );
is( scalar( () = glob "$LE/orphaned/$failName-*" ), 0, 'with nothing left aside' );

done_testing();
