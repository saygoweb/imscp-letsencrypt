package SGWTest;

# Shared set-up for the backend tests.
#
# The tests run on a host where i-MSCP is installed: the docker stack in the
# sibling i-MSCP checkout, or the CI image built from it. They need root, as the
# engine directory and /etc/imscp are unreadable to anyone else.
#
# Nothing a test does may touch the host's real data. The tables the plugin
# reads and writes are shadowed by TEMPORARY tables of the same name on the one
# connection iMSCP::Database holds, so every row a test writes lives only as
# long as the test and no other process can see it. Files are only ever created
# under names made up by the test, and removed again when it ends.

use strict;
use warnings;
use Cwd qw/ abs_path /;
use File::Basename qw/ dirname /;
use File::Path qw/ remove_tree /;
use Test::More;
use Exporter 'import';

our @EXPORT_OK = qw/
    plugin_root engine_dir require_root load_plugin boot plugin shadow_tables create_letsencrypt_table
    fixture_domain fixture_letsencrypt fixture_ssl_cert row rows test_name cleanup_path cleanup_dir
/;

# The plugin checkout under test, wherever it sits.
my $ROOT = abs_path( dirname( __FILE__ ) . '/../..' );

# Where the engine is. IMSCP_ENGINE_DIR overrides it for an install that is not
# in the default location. Its CPAN dependencies live beside it in PerlVendor,
# the same pair imscp-rqst-mngr puts on @INC.
my $ENGINE_DIR = $ENV{'IMSCP_ENGINE_DIR'} || '/var/www/imscp/engine';
my $ENGINE_LIB = "$ENGINE_DIR/PerlLib";
for my $dir (reverse $ENGINE_LIB, "$ENGINE_DIR/PerlVendor") {
    unshift @INC, $dir unless grep { $_ eq $dir } @INC;
}

my @cleanupPaths;
my @cleanupDirs;
my $connectionId;

sub plugin_root { $ROOT }
sub engine_dir { $ENGINE_DIR }

=item require_root()

 Skip the whole test file unless it can reach the i-MSCP installation

=cut

sub require_root
{
    plan skip_all => 'needs root: the i-MSCP engine and configuration are readable by root only'
        if $> != 0;
    plan skip_all => "no i-MSCP engine at $ENGINE_DIR (set IMSCP_ENGINE_DIR)"
        unless -d "$ENGINE_LIB/iMSCP";
}

=item load_plugin()

 Load the backend module of the checkout under test

 The file is backend/SGW_LetsEncrypt.pm but the package is Plugin::SGW_LetsEncrypt, so it is loaded
 by path the way i-MSCP loads it.

=cut

sub load_plugin
{
    my $file = "$ROOT/backend/SGW_LetsEncrypt.pm";
    return 1 if $INC{$file};
    require $file;
}

=item boot()

 Boot the i-MSCP backend the way a plugin is run by the engine, without taking the backend lock

=cut

sub boot
{
    require iMSCP::Bootstrapper;
    iMSCP::Bootstrapper->getInstance()->boot(
        {
            mode            => 'backend',
            nolock          => 1,
            norequirements  => 1,
            config_readonly => 1
        }
    );

    # A reconnect would silently drop the temporary tables and let the plugin write to the real
    # ones, so turn it off and remember which connection the tables belong to.
    my $dbh = iMSCP::Database->factory()->getRawDb();
    $dbh->{ lc( $dbh->{'Driver'}->{'Name'} ) . '_auto_reconnect' } = 0;
    ($connectionId) = $dbh->selectrow_array( 'SELECT CONNECTION_ID()' );
}

=item plugin()

 Return the plugin instance, in testmode and using the certbot mock of the checkout under test

=cut

sub plugin
{
    load_plugin();
    my $plugin = Plugin::SGW_LetsEncrypt->getInstance();
    $plugin->{'testmode'} = 1;
    $plugin->{'certbotTest'} = "$ROOT/backend/certbot-auto-test.pm";
    $plugin;
}

sub _dbh
{
    my $dbh = iMSCP::Database->factory()->getRawDb();
    my ($id) = $dbh->selectrow_array( 'SELECT CONNECTION_ID()' );
    BAIL_OUT( 'the database connection changed under the test; temporary tables are gone' )
        if defined $connectionId && $id != $connectionId;
    $dbh;
}

=item shadow_tables(@tables)

 Shadow each of the given i-MSCP tables with an empty TEMPORARY copy

=cut

sub shadow_tables
{
    my $dbh = _dbh();
    for my $table (@_) {
        my (undef, $ddl) = $dbh->selectrow_array( "SHOW CREATE TABLE `$table`" );
        $ddl =~ s/^CREATE TABLE/CREATE TEMPORARY TABLE/ or die "unexpected DDL for $table";
        # Temporary tables cannot take part in foreign keys
        $ddl =~ s/,\s*CONSTRAINT [^\n]*FOREIGN KEY[^\n]*//g;
        $dbh->do( $ddl );
    }
}

=item create_letsencrypt_table()

 Create the plugin's letsencrypt table as a TEMPORARY table, from the plugin's own migrations

 Runs every migration under sql/ in order, so the schema the tests see is the one an install or
 update produces. This works whether or not the plugin is installed on the host.

=cut

sub create_letsencrypt_table
{
    my $dbh = _dbh();
    for my $file (sort glob "$ROOT/sql/*.php") {
        my $sql = `php -r 'echo (include \$argv[1])["up"];' '$file'`;
        die "could not read the migration $file" if $? || !length $sql;
        $sql =~ s/CREATE TABLE IF NOT EXISTS/CREATE TEMPORARY TABLE/;
        $dbh->do( $sql );
    }
}

=item test_name($label)

 Return a domain name unique to this test run, under the .test TLD which never resolves

=cut

sub test_name
{
    my ($label) = @_;
    "$label-$$.sgw-le.test";
}

=item fixture_domain($type, $name)

 Insert a domain (dmn), domain alias (als) or subdomain (sub) row into the shadowed tables

 Return int The id of the new row

=cut

sub fixture_domain
{
    my ($type, $name) = @_;

    my %rows = (
        dmn => [ 'domain', domain_name => $name, domain_admin_id => 1, domain_status => 'ok' ],
        als => [ 'domain_aliasses', domain_id => 1, alias_name => $name, alias_status => 'ok' ],
        sub => [ 'subdomain', domain_id => 1, subdomain_name => $name, subdomain_status => 'ok' ]
    );
    my $row = $rows{$type} or die "unknown domain type $type";
    _insert( @{$row} );
}

# Insert a row, giving every NOT NULL column without a default a zero value, so
# that a fixture only names the columns the test is about.
sub _insert
{
    my ($table, %values) = @_;
    my $dbh = _dbh();

    my $required = $dbh->selectall_arrayref(
        "
            SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
            AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL AND EXTRA NOT LIKE '%auto_increment%'
        ",
        undef, $table
    );
    for (@{$required}) {
        my ($column, $type) = @{$_};
        $values{$column} //= $type =~ /int|decimal|float|double/ ? 0 : '';
    }

    my @columns = sort keys %values;
    $dbh->do(
        sprintf(
            'INSERT INTO `%s` (%s) VALUES (%s)',
            $table, join( ', ', map { "`$_`" } @columns ), join( ', ', ('?') x @columns )
        ),
        undef, @values{@columns}
    ) or die $dbh->errstr;

    $dbh->last_insert_id( undef, undef, undef, undef );
}

=item fixture_letsencrypt(%fields)

 Insert a letsencrypt row shaped the way letsencrypt_edit.php writes it

 Pass type and id for the domain; cert_name, http_forward and status are taken from %fields.

 Return int The letsencrypt_id of the new row

=cut

sub fixture_letsencrypt
{
    my (%f) = @_;
    my $dbh = _dbh();
    $dbh->do(
        '
            INSERT INTO letsencrypt (
                admin_id, domain_id, alias_id, subdomain_id, cert_name, http_forward, status, state
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
        ',
        undef,
        ($f{'type'} eq 'dmn' ? $f{'id'} : 0),
        ($f{'type'} eq 'als' ? $f{'id'} : undef),
        ($f{'type'} eq 'sub' ? $f{'id'} : undef),
        $f{'cert_name'}, $f{'http_forward'} // 0, $f{'status'} // 'toadd', ''
    );
    $dbh->last_insert_id( undef, undef, undef, undef );
}

=item fixture_ssl_cert($type, $id, %fields)

 Insert an ssl_certs row

=cut

sub fixture_ssl_cert
{
    my ($type, $id, %f) = @_;
    _dbh()->do(
        'INSERT INTO ssl_certs (domain_type, domain_id, private_key, certificate, ca_bundle, status) VALUES (?, ?, ?, ?, ?, ?)',
        undef, $type, $id, $f{'private_key'} // '', $f{'certificate'} // '', '', $f{'status'} // 'ok'
    );
}

=item row($sql, @bind) / rows($sql, @bind)

 Return the first row as a hashref, or all rows as a list of hashrefs

=cut

sub row
{
    my ($sql, @bind) = @_;
    _dbh()->selectrow_hashref( $sql, undef, @bind );
}

sub rows
{
    my ($sql, @bind) = @_;
    @{ _dbh()->selectall_arrayref( $sql, { Slice => {} }, @bind ) };
}

=item cleanup_path($path)

 Remove the given file or directory when the test ends

=cut

sub cleanup_path
{
    push @cleanupPaths, @_;
    $_[0];
}

=item cleanup_dir($dir)

 Remove the given directory when the test ends, if the test created it and left it empty

=cut

sub cleanup_dir
{
    push @cleanupDirs, $_[0] unless -e $_[0];
    $_[0];
}

END {
    remove_tree( $_ ) for grep { -e $_ } @cleanupPaths;
    rmdir $_ for reverse @cleanupDirs;
}

1;
