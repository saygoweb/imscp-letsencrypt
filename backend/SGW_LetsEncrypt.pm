=head1 NAME

 Plugin::SGW_LetsEncrypt

=cut

# i-MSCP LetsEncrypt plugin
# Copyright (C) 2017 Cambell Prince <cambell.prince@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

package Plugin::SGW_LetsEncrypt;

use strict;
use warnings;
use iMSCP::Database;
use iMSCP::Debug;
use iMSCP::Dir;
use iMSCP::EventManager;
use iMSCP::Execute;
use iMSCP::File;
use iMSCP::OpenSSL;
use iMSCP::Rights;
use iMSCP::Service;
use iMSCP::TemplateParser;
use Servers::httpd;
use Socket;
use version;
use parent 'Common::SingletonClass';

use Data::Dumper;

=head1 DESCRIPTION

 This package provides the backend part for the i-MSCP LetsEncrypt plugin.

=head1 PUBLIC METHODS

=over 4

=item install()

 Perform install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
    my $self = shift;

    my $rs = $self->_checkRequirements();
    $rs ||= $self->_letsencryptInstall();
    $rs ||= $self->_letsencryptConfig( 'configure' );
    return $rs if $rs;

    0;
}

=item uninstall()

 Perform uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
    my $self = shift;

    # my $rs = $self->{'db'}->doQuery( 'd', "DELETE FROM domain_dns WHERE owned_by = 'LetsEncrypt_Plugin'" );
    # unless (ref $rs eq 'HASH') {
    #     error( $rs );
    #     return $rs;
    # }

    my $rs = $self->_letsencryptConfig( 'deconfigure' );
    return $rs if $rs;

    # TODO Currently we stop short of removing existing certs and unintsalling certbotauto CP 2017-06

    # $rs = iMSCP::Dir->new( dirname => '/etc/letsencrypt' )->remove();

    return $rs;
}

=item update($fromVersion)

 Perform update tasks

 Param string $fromVersion Version from which the plugin is being updated
 Return int 0 on success, other on failure

=cut

sub update
{
    my ($self, $fromVersion) = @_;
    my $rs = 0;

    # Re-run the installer just in case
    $rs ||= $self->_letsencryptInstall();
    $rs ||= $self->_letsencryptConfig( 'configure' );

    # Trigger a rebuild on all domains with LetsEncrypt enabled
    if (version->parse( $fromVersion ) < version->parse( '1.4.0' )) {
        $self->{'db'}->doQuery(
            'q',
            "UPDATE letsencrypt SET status='tochange' WHERE status IN('ok')"
        );
        $self->run();
    }

    return $rs if $rs;

    0;
}

=item change()

 Perform change tasks

 Return int 0 on success, other on failure

=cut

sub change
{
    0;
}

=item enable()

 Perform enable tasks

 Return int 0 on success, other on failure

=cut

sub enable
{
    my $self = shift;

    # my $rs = $self->{'db'}->doQuery(
    #     'u', 'UPDATE domain_dns SET domain_dns_status = ? WHERE owned_by = ?', 'toenable', 'LetsEncrypt_Plugin'
    # );
    # unless (ref $rs eq 'HASH') {
    #     error( $rs );
    #     return $rs;
    # }

    # $rs = setRights(
    #     '/etc/letsencrypt',
    #     {
    #         user      => 'letsencrypt',
    #         group     => 'letsencrypt',
    #         dirmode   => '0750',
    #         filemode  => '0640',
    #         recursive => 1
    #     }
    # );
    # return $rs if $rs;

    0;
}

=item disable()

 Perform disable tasks

 Return int 0 on success, other on failure

=cut

sub disable
{
    my $self = shift;

    # my $rs = $self->{'db'}->doQuery(
    #     'u', 'UPDATE domain_dns SET domain_dns_status = ? WHERE owned_by = ?', 'todisable', 'LetsEncrypt_Plugin'
    # );
    # unless (ref $rs eq 'HASH') {
    #     error( $rs );
    #     return $rs;
    # }

    0;
}

=item run()

 Create new entry for the LetsEncrypt

 Return int 0 on success, other on failure

=cut

sub run
{
    my $self = shift;

    # Find the domains for which we need to generate certificates
    my $rows = $self->{'db'}->doQuery(
        'letsencrypt_id',
        "
            SELECT letsencrypt_id, domain_id, alias_id, subdomain_id, cert_name, http_forward, status
            FROM letsencrypt WHERE status IN('toadd', 'tochange', 'todelete')
        "
    );
    unless (ref $rows eq 'HASH') {
        error( $rows );
        return 1;
    }

    my @sql;
    for(values %{$rows}) {
        my ($type, $id) = $self->_domainTypeAndId($_->{'domain_id'}, $_->{'alias_id'}, $_->{'subdomain_id'});
        if ($_->{'status'} =~ /^to(?:add|change)$/) {
            my $rs = $self->_addCertificate( $type, $id, $_->{'cert_name'} );
            $rs |= $self->_updateForward( $type, $id, $_->{'cert_name'}, $_->{'http_forward'} );
            @sql = (
                'UPDATE letsencrypt SET status = ? WHERE letsencrypt_id = ?',
                ($rs ? scalar getMessageByType( 'error' ) || 'Unknown error' : 'ok'), $_->{'letsencrypt_id'}
            );
        } elsif ($_->{'status'} eq 'todelete') {
            my $rs = $self->_deleteCertificate( $type, $id, $_->{'cert_name'} );
            $rs |= $self->_updateForward( $type, $id, $_->{'cert_name'}, 0 );
            if ($rs) {
                @sql = (
                    'UPDATE letsencrypt SET status = ? WHERE letsencrypt_id = ?',
                    (scalar getMessageByType( 'error' ) || 'Unknown error'), $_->{'letsencrypt_id'}
                );
            } else {
                @sql = ('DELETE FROM letsencrypt WHERE letsencrypt_id = ?', $_->{'letsencrypt_id'});
            }
        }
        # Update the status of the last operation
        # Comment out the below for dev testing CP 2017-06
        my $qrs = $self->{'db'}->doQuery( 'dummy', @sql );
        unless (ref $qrs eq 'HASH') {
            error( $qrs );
            return 1;
        }
    }

    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Initialize plugin

 Return Plugin::LetsEncrypt or die on failure

=cut

sub _init
{
    my $self = shift;

    # testmode enables the mocked certbot-auto that creates self-signed certificates
    # enabled = 1, disabled = 0
    $self->{'testmode'} = 0;

    $self->{'db'} = iMSCP::Database->factory();
    $self->{'httpd'} = Servers::httpd->factory();

    $self->{'certsDir'} = "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs";
    my $rs = iMSCP::Dir->new( dirname => $self->{'certsDir'} )->make(
        { mode => 0750, user => $main::imscpConfig{'ROOT_USER'}, group => $main::imscpConfig{'ROOT_GROUP'} }
    );
    fatal( sprintf( 'Could not create %s SSL certificate directory', $self->{'certsDir'} ) ) if $rs;

    iMSCP::EventManager->getInstance()->register( 'afterHttpdBuildConf', sub { $self->_onAfterHttpdBuildConf( @_ ); } );

    $self;
}

=item _domainTypeAndId($domainId, $aliasId, $subdomainId)

 Returns ($domainType, $id)

 It is expected that one and only one of the given ID's would be > 0

 Param int $domainId Domain unique identifier ( 0 if this is not a domain )
 Param int $aliasId Domain alias unique identifier ( 0 if no domain alias )
 Param int $subdomainId Domain subdomain unique identifier ( 0 if no domain alias )

=cut

sub _domainTypeAndId
{
    my ($self, $domainId, $aliasId, $subdomainId) = @_;
    if ($domainId > 0) {
        return ('dmn', $domainId);
    } elsif ($aliasId) {
        return ('als', $aliasId);
    } elsif ($subdomainId) {
        return ('sub', $subdomainId);
    }
    return ('', 0);
}

sub _lookup
{
    my ($domain) = @_;
    my $rs = 0;

    my ($stdout, $stderr);
    my $command = "host " . $domain . " 8.8.8.8";
    $rs = execute(
        $command,
        \$stdout, \$stderr
    );
    # print( $command );
    # print( $stdout ) if $stdout;
    return 1 if $stdout =~ /Host \w+ not found/m;
    return 0 if $stdout =~ /is an alias for/m;
    return 0 if $stdout =~ /has address/m;

    return 2;
}

=item _addCertificate($domainId, $certName, $aliasId, $subdomainId)

 Adds LetsEncrypt SSL certificate to the given domain or alias

 This assumes that the domain is currently active and enabled for http.

 Param int $domainId Domain unique identifier
 Param int $aliasId Domain alias unique identifier ( 0 if no domain alias )
 Param string $domain Domain name
 Return int 0 on success, other on failure

=cut

sub _addCertificate
{
    my ($self, $type, $id, $certName) = @_;
    # This action must be idempotent ( this allows us to handle 'tochange' status which include key renewal )

    debug("_addCertificate ");

    if (!$self->{'testmode'} && _lookup($certName) != 0) {
        error("Cannot resolve $certName");
        return 1;
    }

    # Fake out the SSL_SUPPORT in the Domains module by updating the ssl_certs table and creating a fake cert file
    my $rs = 0;
    $rs = $self->_updateSelfSignedCertificate($type, $id);
    $rs == 0 or return $rs;

    my $certNameWWW = 'www.' . $certName;
    my $haveWWW = !$self->{'testmode'} && (_lookup($certNameWWW) == 0) ? 1 : 0;

    # Call certbot to create the key and certificate under /etc/letsencrypt
    my $certbot = 'certbot';
    if ($self->{'testmode'}) {
        $certbot = $main::imscpConfig{'PLUGINS_DIR'}.'/SGW_LetsEncrypt/backend/certbot-auto-test.pm';
    }
    my ($stdout, $stderr);
    my $command = $certbot . " certonly --apache --no-bootstrap --non-interactive -v -d " . escapeShell($certName);
    if ($haveWWW) {
        $command = $command . " --expand -d " . escapeShell($certNameWWW);
    }
    $rs = execute(
        $command,
        \$stdout, \$stderr
    );
    debug( $command );
    debug( $stdout ) if $stdout;     
    $rs == 0 or die( $stderr || "unknown error $rs" );

    # Trigger an onchange to rebuild the domain, our event listener will then help process the domain config rebuild.
    $self->_triggerDomainOnChange($type, $id);
 
    0;
}

sub _updateSelfSignedCertificate
{
    my ($self, $type, $id) = @_;
    my $rs = 0;
    my $result = $self->{'db'}->doQuery(
        'cert_id',
        'SELECT * FROM ssl_certs WHERE domain_type = ? AND domain_id = ?',
        $type, $id
    );
    my $keyTempFile = File::Temp->new(UNLINK => 1);
    my $keyFile = iMSCP::File->new(filename => $keyTempFile->filename);
    my $certTempFile = File::Temp->new(UNLINK => 1);
    my $certFile = iMSCP::File->new(filename => $certTempFile->filename);
    if (%{$result}) {
        my $certId = each %{$result};
        my $record = $result->{$certId};
        # If we have a key or certificate check to see if they are valid
        if ($record->{'private_key'} || $record->{'certificate'}) {
            $keyFile->set($record->{'private_key'});
            $keyFile->save();
            $certFile->set($record->{'certificate'});
            $certFile->save();
            my $openSSL = iMSCP::OpenSSL->new(
                private_key_container_path     => $keyTempFile->filename,
                certificate_container_path     => $certTempFile->filename
            );
            return 0 if $openSSL->validateCertificateChain() == 0;
        }
    }

    # Create a new key and self signed certificate
    my $cmd = [
        'openssl', 'req', '-x509', '-nodes', '-days', '36500', '-subj', '/CN=test1.local', '-newkey', 'rsa',
        '-keyout', $keyTempFile,
        '-out', $certTempFile
    ];
    $rs = execute($cmd, \ my $stdout, \ my $stderr);
    print($stdout . "\n") if $stdout;
    print($stderr . "\n") if $stderr;

    my $key = $keyFile->get();
    my $cert = $certFile->get();

    if (%{$result}) {
        # Update
        $rs = $self->{'db'}->doQuery(
            'u',
            "UPDATE ssl_certs SET status='tochange', private_key=?, certificate=? WHERE domain_type=? AND domain_id=? ",
            $key, $cert, $type, $id
        );
    } else {
        # Insert
        $rs = $self->{'db'}->doQuery(
            'i',
            "INSERT INTO ssl_certs (status, private_key, certificate, domain_type, domain_id) VALUES ('toadd', ?, ?, ?, ?)",
            $key, $cert, $type, $id
        );
    }
    unless (ref $rs eq 'HASH') {
        error($rs);
        return 1;
    }

    0;
}

sub _triggerDomainOnChange
{
    my ($self, $type, $id) = @_;

    # Trigger an onchange to rebuild the domain, our event listener will then help process the domain config rebuild.
    my $rs;
    if ($type eq 'dmn') {
        $rs = $self->{'db'}->doQuery(
            'u',
            "UPDATE domain SET domain_status = 'toadd' WHERE domain_id = ? ",
            $id
        );
    } elsif ($type eq 'als') {
        $rs = $self->{'db'}->doQuery(
            'u',
            "UPDATE domain_aliasses SET alias_status = 'toadd' WHERE alias_id = ? ",
            $id
        );
    } elsif ($type eq 'sub') {
        $rs = $self->{'db'}->doQuery(
            'u',
            "UPDATE subdomain SET subdomain_status = 'toadd' WHERE subdomain_id = ? ",
            $id
        );
    } else {
        error ( 'Unsupported domain type ' . $type);
        return 2;
    }
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    0;
}

=item _onAfterHttpdBuildConf($cfgTpl, $filename, $data)

 Param Hash %data Domain data as per the Domains module
 Return int 0 on success, other on failure

=cut

sub _onAfterHttpdBuildConf
{
    my ($self, $cfgTpl, $filename, $data) = @_;
    return unless $filename eq 'domain.tpl';

    my $domain = $data->{'DOMAIN_NAME'};
    my $domain_store_path = '/etc/letsencrypt/live/' . $domain . '/';
    my $key_file = $domain_store_path . 'privkey.pem';
    my $cert_file = $domain_store_path . 'cert.pem';
    my $chain_file = $domain_store_path . 'chain.pem';

    my $snippet = <<EOF;

    SSLEngine On
    SSLCertificateFile _CERTIFICATEFILE_
    SSLCertificateKeyFile _CERTIFICATEKEYFILE_
    SSLCertificateChainFile _CERTIFICATECHAINFILE_

EOF

    $snippet =~ s/_CERTIFICATEFILE_/$cert_file/g;
    $snippet =~ s/_CERTIFICATEKEYFILE_/$key_file/g;
    $snippet =~ s/_CERTIFICATECHAINFILE_/$chain_file/g;

    $$cfgTpl =~ s/^\s+SSLEngine.*\n\s+SSLCertificateFile.*\n/$snippet/gm;

    0;
}

=item _updateForward($type, $id, $certName, $doForward)

 Updates the forward (redirect) status of the domain 'certName' to enable
 either http or the redirect of http -> https for the domain.

 Param int $domainId Domain unique identifier
 Param string $certName Primary name of the target certificate / domain
 Param boolean $doForward True to do the forward / redirect
 Return int 0 on success, other on failure

=cut

sub _updateForward
{
    my ($self, $type, $id, $certName, $doForward) = @_;

    # Update the domains table with the forward info
    my $hsts = ($doForward eq '1') ? 'on' : 'off';
    my $rs = $self->{'db'}->doQuery(
        'u',
        "UPDATE ssl_certs SET allow_hsts = ? WHERE domain_type = ? AND domain_id = ? ",
        $hsts, $type, $id
    );
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    # This requires a rebuild of the domain, but assume that this is triggered elsewhere

    0;
}

=item _deleteCertificate($type, $id, $certName)

 Removes LetsEncrypt SSL certificate from the domain

 Param string $type Domain type (dmn|als|sub)
 Param int $id Domain unique identifier
 Param int $aliasId Domain alias unique identifier (0 if no domain alias)
 Return int 0 on success, other on failure

=cut

sub _deleteCertificate
{
    my ($self, $type, $id, $certName) = @_;

    # Fake out the SSL_SUPPORT in the Domains module by updating the ssl_certs table and creating a fake cert file
    my $rs = 0;
    $rs = $self->{'db'}->doQuery(
        'i',
        "DELETE FROM ssl_certs WHERE domain_type = ? AND domain_id = ?",
        $type, $id
    );
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    # Delete the fake cert file, its not valid PEM but that doesn't matter.
    my $certificate = iMSCP::File->new( filename => "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs/$certName.pem");
    debug($certificate->{'filename'});
    if (-f $certificate->{'filename'}) {
        $certificate->delFile();
    }

    # Trigger an onchange to rebuild the domain, our event listener will then help process the domain config rebuild.
    $self->_triggerDomainOnChange($type, $id);
 
    0;
}

=item _letsencryptInstall()

 Install LetsEncrypt software; certbot-auto

 Return int 0 on success, other on failure

=cut

sub _letsencryptInstall
{
    # Remove certbot-auto if it exists
    my $oldFile = iMSCP::File->new( filename => '/usr/local/bin/certbot-auto' );
    if (-e $oldFile->{filename}) {
        $oldFile->delFile()
        execute('wget --no-check-certificate https://dl.eff.org/certbot-auto -P /usr/local/bin/');
    }
    # Install snap and then certbot via snap
    my $newFile = iMSCP::File->new( filename => '/usr/local/bin/certbot' );
    if (not -e $newFile->{filename}) {
        execute('apt-get -y install snap');
        execute('snap install core; snap refresh core');
        execute('snap install --classic certbot');
    }

    my $cronContent = <<EOF;
#!/bin/sh
if [ -f /usr/sbin/csf ]; then
    /usr/sbin/csf -ta 0.0.0.0/0 180 -d out
fi
/usr/local/bin/certbot renew --quiet --no-self-upgrade
if [ -f /usr/sbin/csf ]; then
    /usr/sbin/csf -tr 0.0.0.0/0
fi
EOF

    my $cron = iMSCP::File->new( filename => '/etc/cron.weekly/letsencrypt');
    $cron->set($cronContent);
    $cron->save();
    $cron->mode(0755);

    0;
}

=item _letsencryptConfig($action)

 Configure or deconfigure LetsEncrypt

 Param string $action Action to perform ( configure|deconfigure )
 Return int 0 on success, other on failure

=cut

sub _letsencryptConfig
{
    my ($self, $action) = @_;

    # /etc/default/letsencrypt configuration file
    # my $file = iMSCP::File->new( filename => '/etc/default/letsencrypt' );
    # my $fileContent = $file->get();
    # unless (defined $fileContent) {
    #     error( sprintf( 'Could not read %s file', $file->{'filename'} ) );
    #     return 1;
    # }

    if ($action eq 'configure') {
    } elsif ($action eq 'deconfigure') {
        # $fileContent = replaceBloc( "# Begin Plugin::LetsEncrypt\n", "# Ending Plugin::LetsEncrypt\n", '', $fileContent );
    }

    # my $rs = $file->set( $fileContent );
    # $rs ||= $file->save();
    # return $rs if $rs;

}

=item _checkRequirements()

 Check for requirements

 Return int 0 if all requirements are met, other otherwise

=cut

sub _checkRequirements
{
    my $ret = 0;

    # wget

    # for(qw/ letsencrypt letsencrypt-tools /) {
    #     if (execute( "dpkg-query -W -f='\${Status}' $_ 2>/dev/null | grep -q '\\sinstalled\$'" )) {
    #         error( sprintf( 'The `%s` package is not installed on your system', $_ ) );
    #         $ret ||= 1;
    #     }
    # }

    $ret;
}

=back

=head1 AUTHORS

 Cambell Prince <cambell.prince@gmail.com>

=cut

1;
__END__
