use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw/ make_path /;
use Test::More;
use SGWTest qw/ require_root load_plugin test_name cleanup_path cleanup_dir /;

# _onAfterHttpdBuildConf is the listener that points a vhost at the
# certificates under /etc/letsencrypt instead of the ones i-MSCP keeps.

require_root();
load_plugin() or BAIL_OUT( 'cannot load the plugin' );

my $plugin = bless {}, 'Plugin::SGW_LetsEncrypt';
my $domain = test_name( 'conf' );

# The vhost template of the i-MSCP installation the tests run on, so that the
# listener is checked against what the engine actually renders. The listener
# runs after the build, but it only matches the directive names, so the
# placeholders left in the raw template make no difference.
my $tplFile = $ENV{'IMSCP_DOMAIN_TPL'} || '/etc/imscp/apache/parts/domain.tpl';
open my $tfh, '<', $tplFile or BAIL_OUT( "cannot read $tplFile: $!" );
my $tpl = do { local $/; <$tfh> };
close $tfh;
like( $tpl, qr/^\s+SSLEngine On$/m, "$tplFile has an SSL section" );

my $cfg = $tpl;
is( $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain.tpl', { DOMAIN_NAME => $domain } ), 0, 'domain.tpl is handled' );
like(
    $cfg, qr{^\s+SSLCertificateFile /etc/letsencrypt/live/\Q$domain\E/cert\.pem$}m,
    'the certificate is the one certbot issued'
);
like( $cfg, qr{^\s+SSLCertificateKeyFile /etc/letsencrypt/live/\Q$domain\E/privkey\.pem$}m, 'with its key' );
like( $cfg, qr{^\s+SSLCertificateChainFile /etc/letsencrypt/live/\Q$domain\E/chain\.pem$}m, 'and its chain' );
unlike( $cfg, qr{\{CERTIFICATE\}}, 'nothing points at the i-MSCP certificate any more' );
for my $directive (qw/ SSLEngine SSLCertificateFile SSLCertificateKeyFile SSLCertificateChainFile /) {
    is( scalar( () = $cfg =~ /^\s+$directive\s/mg ), 1, "$directive is set once" );
}
like( $cfg, qr{^\s+Header always set Strict-Transport-Security}m, 'the rest of the SSL section is kept' );

$cfg = $tpl;
ok(
    !$plugin->_onAfterHttpdBuildConf( \$cfg, 'domain_redirect.tpl', { DOMAIN_NAME => $domain } ),
    'other templates are passed over'
);
is( $cfg, $tpl, 'and left as they were' );

# A disabled domain must stop being renewed, or certbot renew fails on it every
# week. Disabling is reversible, so its renewal config is kept aside rather than
# deleted, and put back when the domain is enabled again (#42).
cleanup_dir( $_ ) for qw{ /etc/letsencrypt /etc/letsencrypt/renewal /etc/letsencrypt/renewal-disabled };
my $renewal = cleanup_path( "/etc/letsencrypt/renewal/$domain.conf" );
my $parked = cleanup_path( "/etc/letsencrypt/renewal-disabled/$domain.conf" );
make_path( '/etc/letsencrypt/renewal' );

sub write_file
{
    my ($file, $content) = @_;
    open my $fh, '>', $file or die "cannot write $file: $!";
    print $fh $content;
    close $fh;
}

sub read_file
{
    my ($file) = @_;
    open my $fh, '<', $file or return undef;
    local $/;
    <$fh>;
}

write_file( $renewal, "# test\n" );

$cfg = $tpl;
is(
    $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain_disabled.tpl', { DOMAIN_NAME => $domain } ), 0,
    'domain_disabled.tpl is handled'
);
ok( !-e $renewal, 'certbot no longer renews a disabled domain' );
is( read_file( $parked ), "# test\n", 'its renewal config is kept aside' );
is( $cfg, $tpl, 'the disabled page itself is left alone' );

is(
    $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain_disabled.tpl', { DOMAIN_NAME => $domain } ), 0,
    'disabling it again is fine'
);
is( read_file( $parked ), "# test\n", 'and keeps the config aside' );

$cfg = $tpl;
is( $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain.tpl', { DOMAIN_NAME => $domain } ), 0, 'the domain is enabled again' );
is( read_file( $renewal ), "# test\n", 'its renewal config is back' );
ok( !-e $parked, 'and no longer kept aside' );

# certbot was given a renewal config of its own while the domain was disabled:
# that one is current, the parked one is not.
write_file( $parked, "# old\n" );
write_file( $renewal, "cert = /etc/hostname\n# new\n" );
$plugin->_onAfterHttpdBuildConf( \$cfg, 'domain.tpl', { DOMAIN_NAME => $domain } );
is( read_file( $renewal ), "cert = /etc/hostname\n# new\n", 'a renewal config in use is not overwritten by a parked one' );
ok( !-e $parked, 'and the parked one is dropped' );

# An empty renewal config, as a failed certbot 5.9 run leaves behind, is no config at all.
write_file( $parked, "# parked\n" );
write_file( $renewal, '' );
$plugin->_onAfterHttpdBuildConf( \$cfg, 'domain.tpl', { DOMAIN_NAME => $domain } );
is( read_file( $renewal ), "# parked\n", 'an empty renewal config is replaced by the parked one' );

unlink $renewal;
is(
    $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain_disabled.tpl', { DOMAIN_NAME => $domain } ), 0,
    'a domain with no renewal config is fine too'
);
ok( !-e $parked, 'and has nothing kept aside' );

done_testing();
