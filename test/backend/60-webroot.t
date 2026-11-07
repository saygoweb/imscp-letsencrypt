use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw/ make_path /;
use File::Temp;
use Test::More;
use SGWTest qw/
    require_root boot plugin sandbox shadow_tables create_letsencrypt_table fixture_domain fixture_letsencrypt
    test_name cleanup_path cleanup_dir
/;

# certbot answers the http-01 challenge from a webroot the plugin's Apache conf
# serves on every vhost, rather than through its Apache plugin, which parsed the
# whole Apache config for each certificate and reloaded Apache several times
# over. Lineages requested before keep renewing the way they were requested, so
# install and update rewrite the renewal configs of the plugin's lineages for the
# webroot, and renewal hooks reload Apache once a run.

require_root();
boot();
shadow_tables( qw/ ssl_certs domain domain_aliasses subdomain / );
create_letsencrypt_table();

my $plugin = plugin();
my $LE = '/etc/letsencrypt';
my $webroot = $plugin->{'webroot'};
cleanup_dir( $_ ) for map { "$LE$_" } '', qw{ /live /archive /renewal /renewal-disabled };
END { cleanup_path( glob "$LE/{live,archive,renewal,renewal-disabled}/*-$$.*" ); }

sub slurp
{
    open my $fh, '<', $_[0] or return undef;
    local $/;
    <$fh>;
}

sub spew
{
    my ($file, $content) = @_;
    open my $fh, '>', $file or die "cannot write $file: $!";
    print $fh $content;
    close $fh;
    $file;
}

# A renewal config the way certbot 5.9 writes it for certonly --apache, as aws1 has them
sub apache_conf
{
    my ($name) = @_;
    <<"EOF";
# renewal_before_expiry = 30 days
version = 5.9.0
archive_dir = $LE/archive/$name
cert = $LE/live/$name/cert.pem
privkey = $LE/live/$name/privkey.pem
chain = $LE/live/$name/chain.pem
fullchain = $LE/live/$name/fullchain.pem

# Options used in the renewal process
[renewalparams]
account = 0123456789abcdef0123456789abcdef
authenticator = apache
installer = apache
server = https://acme-v02.api.letsencrypt.org/directory
key_type = ecdsa
EOF
}

# --- _webrootRenewalConf --------------------------------------------------------

my $before = apache_conf( 'a.test' );
my $after = Plugin::SGW_LetsEncrypt::_webrootRenewalConf( $before, '/srv/w', 'a.test', 'www.a.test' );
is( $after, <<"EOF", 'an Apache plugin config is rewritten for the webroot, everything else kept as it was' );
# renewal_before_expiry = 30 days
version = 5.9.0
archive_dir = $LE/archive/a.test
cert = $LE/live/a.test/cert.pem
privkey = $LE/live/a.test/privkey.pem
chain = $LE/live/a.test/chain.pem
fullchain = $LE/live/a.test/fullchain.pem

# Options used in the renewal process
[renewalparams]
account = 0123456789abcdef0123456789abcdef
authenticator = webroot
webroot_path = /srv/w,
server = https://acme-v02.api.letsencrypt.org/directory
key_type = ecdsa
[[webroot_map]]
a.test = /srv/w
www.a.test = /srv/w
EOF
ok( !defined Plugin::SGW_LetsEncrypt::_webrootRenewalConf( $after, '/srv/w', 'a.test' ),
    'and is left alone once it is on the webroot' );

my $odd = <<'EOF';
cert = /x/cert.pem
[renewalparams]
authenticator = "apache"
[[webroot_map]]
old.test = /old
[other]
installer = apache
EOF
is( Plugin::SGW_LetsEncrypt::_webrootRenewalConf( $odd, '/srv/w', 'a.test' ), <<'EOF',
cert = /x/cert.pem
[renewalparams]
authenticator = webroot
webroot_path = /srv/w,
[[webroot_map]]
a.test = /srv/w
[other]
installer = apache
EOF
    'a map left behind is replaced, the map ends [renewalparams], and other sections are not touched' );

is( Plugin::SGW_LetsEncrypt::_webrootRenewalConf( "[renewalparams]\nauthenticator = apache", '/w', 'a.test' ),
    "[renewalparams]\nauthenticator = webroot\nwebroot_path = /w,\n[[webroot_map]]\na.test = /w\n",
    'a config without a final newline is rewritten whole' );
ok( !defined Plugin::SGW_LetsEncrypt::_webrootRenewalConf( "[renewalparams]\nauthenticator = standalone\n", '/w' ),
    'a config of another authenticator is left alone' );
ok( !defined Plugin::SGW_LetsEncrypt::_webrootRenewalConf( "[other]\nauthenticator = apache\n", '/w' ),
    'as is one whose apache is not in [renewalparams]' );
ok( !defined Plugin::SGW_LetsEncrypt::_webrootRenewalConf( '', '/w' ), 'and an empty one' );

# --- _migrateRenewalConfs --------------------------------------------------------

# A lineage with a certificate for the given names, and a renewal config
sub lineage
{
    my ($name, $conf, @names) = @_;
    my $live = cleanup_path( "$LE/live/$name" );
    cleanup_path( "$LE/archive/$name" );
    make_path( $live, "$LE/renewal", "$LE/renewal-disabled" );
    system(
        'openssl', 'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', "$live/privkey.pem",
        '-out', "$live/cert.pem", '-subj', "/CN=$name", '-days', '30',
        '-addext', 'subjectAltName=' . join( ',', map { "DNS:$_" } $name, @names )
    ) == 0 or die 'openssl failed';
    $conf;
}

my $managed = test_name( 'managed' );
my $withWWW = test_name( 'www' );
my $parked = test_name( 'parked' );
my $done = test_name( 'done' );
my $foreign = test_name( 'foreign' );
for my $name ($managed, $withWWW, $parked, $done) {
    fixture_letsencrypt( type => 'dmn', id => fixture_domain( 'dmn', $name ), cert_name => $name, status => 'ok' );
}

my %conf = (
    $managed => spew( lineage( $managed, "$LE/renewal/$managed.conf" ), apache_conf( $managed ) ),
    $withWWW => spew( lineage( $withWWW, "$LE/renewal/$withWWW.conf", "www.$withWWW" ), apache_conf( $withWWW ) ),
    $parked  => spew( lineage( $parked, "$LE/renewal-disabled/$parked.conf" ), apache_conf( $parked ) ),
    $done    => spew( lineage( $done, "$LE/renewal/$done.conf" ), "[renewalparams]\nauthenticator = webroot\n" ),
    # Not the plugin's: the panel's own certificate, say, which is requested another way
    $foreign => spew( lineage( $foreign, "$LE/renewal/$foreign.conf" ), apache_conf( $foreign ) ),
);
chmod 0640, $conf{$managed};
my %original = map { $_ => slurp( $conf{$_} ) } keys %conf;

is( $plugin->_migrateRenewalConfs(), 0, 'the renewal configs are migrated' );

my $mine = slurp( $conf{$managed} );
like( $mine, qr/^authenticator = webroot$/m, "the plugin's lineages renew with the webroot" );
like( $mine, qr/^webroot_path = \Q$webroot\E,$/m, 'from the webroot' );
like( $mine, qr/^\[\[webroot_map\]\]\n\Q$managed\E = \Q$webroot\E\n\z/m, 'which every name is mapped to' );
unlike( $mine, qr/^installer/m, 'with no installer' );
is( (stat $conf{$managed})[2] & 07777, 0640, 'the config keeps its mode' );
like( slurp( $conf{$withWWW} ), qr/^\Q$withWWW\E = \S+\nwww\.\Q$withWWW\E = \S+$/m,
    'the www name is mapped too, as the certificate has it' );
like( slurp( $conf{$parked} ), qr/^authenticator = webroot$/m,
    'a disabled domain is migrated too, so that it renews once it is enabled again' );
is( slurp( $conf{$done} ), $original{$done}, 'a config already on the webroot is not touched' );
is( slurp( $conf{$foreign} ), $original{$foreign}, 'nor is a lineage the plugin does not manage' );

my @backups = glob sandbox() . '/renewal-backup/*';
is( scalar @backups, 1, 'the configs were backed up first, in one place' );
is( slurp( "$backups[0]/renewal/$managed.conf" ), $original{$managed}, 'as they were' );
is( slurp( "$backups[0]/renewal-disabled/$parked.conf" ), $original{$parked}, 'a parked one beside renewal/' );
ok( !-e "$backups[0]/renewal/$done.conf", 'only those rewritten' );
ok( !-e "$backups[0]/renewal/$foreign.conf", 'and only the plugin\'s' );
is( (stat "$backups[0]/renewal/$managed.conf")[2] & 07777, 0600, 'readable by root only' );

my %migrated = map { $_ => slurp( $conf{$_} ) } keys %conf;
sleep 1;    # a second backup would get a directory of its own
is( $plugin->_migrateRenewalConfs(), 0, 'migrating again succeeds' );
is_deeply( { map { $_ => slurp( $conf{$_} ) } keys %conf }, \%migrated, 'and changes nothing' );
is( scalar( () = glob sandbox() . '/renewal-backup/*' ), 1, 'nor backs anything up' );

# --- the plugin's own requests ------------------------------------------------------

my $new = test_name( 'new' );
cleanup_path( "$LE/live/$new", "$LE/archive/$new", "$LE/renewal/$new.conf" );
my $newId = fixture_domain( 'dmn', $new );
fixture_letsencrypt( type => 'dmn', id => $newId, cert_name => $new, status => 'toadd' );
is( $plugin->run(), 0, 'a certificate is requested' );
like( slurp( "$LE/renewal/$new.conf" ), qr/^authenticator = webroot\nwebroot_path = \Q$webroot\E,$/m,
    'certbot was asked to use the webroot, which it renews with' );
is( $plugin->_migrateRenewalConfs(), 0, 'and there is nothing to migrate in it' );

# --- the Apache conf --------------------------------------------------------------

my $apache = Plugin::SGW_LetsEncrypt::_apacheConfContent( '/srv/w' );
like( $apache, qr{^Alias "/\.well-known/acme-challenge/" "/srv/w/\.well-known/acme-challenge/"$}m,
    'the challenge path is served from the webroot, on every vhost' );
like( $apache, qr{<Directory "/srv/w/\.well-known/acme-challenge">.*Require all granted.*</Directory>}s,
    'to anyone' );
like( $apache, qr{^\s*AllowOverride None$}m, 'with no .htaccess read in it' );

# --- the renewal hooks --------------------------------------------------------------

is( $plugin->_installRenewalHooks(), 0, 'the renewal hooks are installed' );
my ($deploy, $post, $flag) = @{$plugin}{qw/ deployHook postHook reloadFlag /};
ok( -x $deploy && -x $post, 'both can be run' );

# Stand-ins for systemctl and service, so that running the post hook reloads nothing
my $bin = File::Temp->newdir();
my $calls = "$bin/calls";
for my $tool (qw/ systemctl service /) {
    spew( "$bin/$tool", "#!/bin/sh\necho \"$tool \$*\" >> '$calls'\n" );
    chmod 0755, "$bin/$tool";
}
local $ENV{'PATH'} = "$bin:$ENV{'PATH'}";

system( $post ) == 0 or fail( 'the post hook runs' );
ok( !-e $calls, 'a run that renewed nothing does not reload Apache' );

system( $deploy ) == 0 or fail( 'the deploy hook runs' ) for 1 .. 3;
ok( -e $flag, 'a renewed certificate raises the flag' );
system( $post ) == 0 or fail( 'the post hook runs' );
my @reloads = split /\n/, slurp( $calls ) // '';
is( scalar @reloads, 1, 'and Apache is reloaded once at the end of the run, however many were renewed' );
like( $reloads[0] // '', qr/^(?:systemctl reload apache2|service apache2 reload)$/, 'by a reload, not a restart' );
ok( !-e $flag, 'and the flag is down for the next run' );

is( $plugin->_installRenewalHooks(), 0, 'installing the hooks again is harmless' );
is( $plugin->_removeRenewalHooks(), 0, 'the hooks are removed' );
ok( !-e $deploy && !-e $post, 'both of them' );

done_testing();
