use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
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

# A disabled domain must stop being renewed, or certbot renew fails on it every week.
cleanup_dir( $_ ) for qw{ /etc/letsencrypt /etc/letsencrypt/renewal };
my $renewal = cleanup_path( "/etc/letsencrypt/renewal/$domain.conf" );
system( 'mkdir', '-p', '/etc/letsencrypt/renewal' );
open my $fh, '>', $renewal or die "cannot write $renewal: $!";
print $fh "# test\n";
close $fh;

$cfg = $tpl;
is(
    $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain_disabled.tpl', { DOMAIN_NAME => $domain } ), 0,
    'domain_disabled.tpl is handled'
);
ok( !-e $renewal, 'the renewal config of a disabled domain is removed' );
is( $cfg, $tpl, 'the disabled page itself is left alone' );

is(
    $plugin->_onAfterHttpdBuildConf( \$cfg, 'domain_disabled.tpl', { DOMAIN_NAME => $domain } ), 0,
    'a domain with no renewal config is fine too'
);

done_testing();
