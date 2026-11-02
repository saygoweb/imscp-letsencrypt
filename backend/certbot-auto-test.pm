#!/usr/bin/perl
# A stand-in for certbot, run by the plugin in testmode. It keeps lineages under
# /etc/letsencrypt the way certbot 5 does - archive/<name>/*1.pem, live/<name>/
# symlinks into it, renewal/<name>.conf - with self-signed certificates, so the
# plugin's handling of them can be tested without asking Let's Encrypt.
#
#   certbot-auto-test.pm certonly [--cert-name NAME] -d DOMAIN [--expand -d DOMAIN]... [flags]
#   certbot-auto-test.pm delete --non-interactive --cert-name NAME
#
# certonly, like certbot:
#   - keeps lineage NAME (--cert-name, else the first -d) when renewal/NAME.conf
#     holds a config, and says "Keeping the existing certificate";
#   - otherwise starts a new lineage named after the first renewal/NAME[-NNNN].conf
#     that does not exist yet, which it creates empty first, and fails with
#     CertStorageError if archive/ or live/ already holds that name - leaving
#     the empty config behind, as certbot 5.9 does (issue #42);
#   - fails, as if the domain did not resolve, for any domain under .fail.local.
# delete removes the lineage, or fails when there is no renewal config for it.

use strict;
use warnings;
use Fcntl qw/ O_CREAT O_EXCL O_WRONLY /;
use File::Copy qw/ copy /;
use File::Path qw/ make_path remove_tree /;
use Getopt::Long;

my $LE = '/etc/letsencrypt';

my $action = shift @ARGV // '';
my ($certName, @domains);
GetOptions(
    'cert-name=s' => \$certName,
    'domain|d=s'  => \@domains,
    map { $_ => sub {} } qw/ apache no-bootstrap non-interactive no-self-update verbose|v expand /
) or die "certbot-auto-test: unknown option\n";

if ($action eq 'certonly') {
    @domains or die "certbot-auto-test: certonly needs -d\n";

    if (my ($bad) = grep { /\.fail\.local$/ } @domains) {
        print STDERR "Certbot failed to authenticate some domains (authenticator: apache). "
            . "The Certificate Authority reported these problems:\n"
            . "  Domain: $bad\n"
            . "  Type:   dns\n"
            . "  Detail: DNS problem: NXDOMAIN looking up A for $bad\n";
        exit 1;
    }

    my $name = $certName // $domains[0];
    if (has_config( $name )) {
        print "Certificate not yet due for renewal\nKeeping the existing certificate\n";
        exit 0;
    }

    make_path( "$LE/renewal" );
    my ($lineage, $fh);
    for (my $n = 0; ; $n++) {
        $lineage = $n ? sprintf( '%s-%04d', $name, $n ) : $name;
        last if sysopen $fh, "$LE/renewal/$lineage.conf", O_CREAT | O_EXCL | O_WRONLY;
        die "certbot-auto-test: $LE/renewal/$lineage.conf: $!\n" unless $!{EEXIST};
    }

    for my $kind (qw/ archive live /) {
        if (-e "$LE/$kind/$lineage") {
            print STDERR "certbot.errors.CertStorageError: $kind directory exists for $lineage\n";
            exit 1;
        }
    }

    my $archive = "$LE/archive/$lineage";
    my $live = "$LE/live/$lineage";
    make_path( $archive, $live, { mode => 0700 } );
    run( 'openssl', 'genrsa', '-out', "$archive/privkey1.pem", '2048' );
    run(
        'openssl', 'req', '-x509', '-new', '-key', "$archive/privkey1.pem", '-subj', "/CN=$domains[0]",
        '-days', '3650', '-out', "$archive/cert1.pem"
    );
    for my $copy (qw/ chain fullchain /) {
        copy( "$archive/cert1.pem", "$archive/${copy}1.pem" ) or die "certbot-auto-test: copy: $!\n";
    }
    for my $file (qw/ privkey cert chain fullchain /) {
        symlink "../../archive/$lineage/${file}1.pem", "$live/$file.pem"
            or die "certbot-auto-test: symlink $live/$file.pem: $!\n";
    }

    print $fh <<EOF;
# renewal config written by certbot-auto-test
version = certbot-auto-test
archive_dir = $archive
cert = $live/cert.pem
privkey = $live/privkey.pem
chain = $live/chain.pem
fullchain = $live/fullchain.pem

[renewalparams]
authenticator = apache
EOF
    close $fh or die "certbot-auto-test: $!\n";

    print "Successfully received certificate.\nCertificate is saved at: $live/fullchain.pem\n";
    exit 0;
}

if ($action eq 'delete') {
    defined $certName or die "certbot-auto-test: delete needs --cert-name\n";
    unless (has_config( $certName )) {
        print STDERR "No certificate found with name $certName (expected $LE/renewal/$certName.conf).\n";
        exit 1;
    }
    remove_tree( "$LE/live/$certName", "$LE/archive/$certName", "$LE/renewal/$certName.conf" );
    print "Deleted all files relating to certificate $certName.\n";
    exit 0;
}

die "certbot-auto-test: unsupported action '$action'\n";

# True when renewal/NAME.conf holds a config: certbot skips an empty one it cannot parse
sub has_config
{
    my ($name) = @_;
    open my $fh, '<', "$LE/renewal/$name.conf" or return 0;
    local $/;
    my $content = <$fh> // '';
    $content =~ /\S/;
}

sub run
{
    system( @_ ) == 0 or die "certbot-auto-test: @_ failed\n";
}
