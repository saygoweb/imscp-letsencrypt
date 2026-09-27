use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use SGWTest qw/ plugin_root engine_dir require_root /;

# Every source file at least parses. Cheap, and catches what a partial deploy
# would otherwise only reveal when the panel or the engine loads the plugin.

require_root();

my $root = plugin_root();
my $engine = engine_dir();

for my $file ("$root/backend/SGW_LetsEncrypt.pm", "$root/backend/certbot-auto-test.pm") {
    my $out = `perl -I'$engine/PerlLib' -I'$engine/PerlVendor' -c '$file' 2>&1`;
    is( $?, 0, "perl -c $file" ) or diag( $out );
}

# The panel runs the plugin under the PHP it was installed with. PHP_BIN picks
# another one, e.g. to check a newer PHP before moving the panel onto it.
my $php = $ENV{'PHP_BIN'} || 'php';
my @php = grep { !m{^\Q$root\E/(?:\.git|\.claude|test)/} }
    split /\n/, `find '$root' -name '*.php'`;
ok( scalar @php, 'found the PHP sources' );
for my $file (sort @php) {
    my $out = `$php -l '$file' 2>&1`;
    is( $?, 0, "php -l $file" ) or diag( $out );
}

done_testing();
