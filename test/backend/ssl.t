use diagnostics; # this gives you more debugging information
use warnings;    # this warns you of bad practices
use strict;      # this prevents silly errors
use Cwd 'abs_path';
use Test::More qw( no_plan ); # for the is() and isnt() functions

use lib (abs_path('../../backend'), abs_path('../../../../../engine/PerlLib'));

use iMSCP::Bootstrapper;

use iMSCP::Execute;
use iMSCP::OpenSSL;
use iMSCP::File;

use LetsEncrypt;

my $bootstrapper = iMSCP::Bootstrapper->getInstance();
$bootstrapper->getInstance()->boot(
    {
        mode            => 'backend',
        nolock          => 1,
        norequirements  => 1,
        config_readonly => 1
    }
);

my $keyTempFile = File::Temp->new(UNLINK => 1);
my $certTempFile = File::Temp->new(UNLINK => 1);

my $cmd = [
    'openssl', 'req', '-x509', '-nodes', '-days', '36500', '-subj', '/CN=test1.local', '-newkey', 'rsa',
    '-keyout', $keyTempFile,
    '-out', $certTempFile
];
my $rs = execute($cmd, \ my $stdout, \ my $stderr);
# print $stdout if $stdout;
# print $stderr if $stderr;
my $keyFile = iMSCP::File->new(filename => $keyTempFile->filename);
# print $keyFile->get();

my $certFile = iMSCP::File->new(filename => $certTempFile->filename);
# print $certFile->get();

my $openSSL = iMSCP::OpenSSL->new(
    # certificate_chains_storage_dir => $self->{'certsDir'},
    # certificate_chain_name         => $self->{'domain_name'},
    private_key_container_path     => $keyTempFile->filename,
    certificate_container_path     => $certTempFile->filename
    # ca_bundle_container_path       => defined $caBundleContainer ? $caBundleContainer : ''
);
is($openSSL->validatePrivateKey(), 0, "ssl validatePrivateKey");
is($openSSL->validateCertificate(), 0, "ssl validateCertificate");
is($openSSL->validateCertificateChain(), 0, "ssl validateCertificateChain");
