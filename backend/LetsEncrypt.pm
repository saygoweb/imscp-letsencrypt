=head1 NAME

 Plugin::LetsEncrypt

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

package Plugin::LetsEncrypt;

use strict;
use warnings;
use iMSCP::Database;
use iMSCP::Debug;
use iMSCP::Dir;
use iMSCP::EventManager;
use iMSCP::Execute;
use iMSCP::File;
use iMSCP::Rights;
use iMSCP::Service;
use iMSCP::TemplateParser;
use Servers::httpd;
use version;
use parent 'Common::SingletonClass';

# use Data::Dumper;

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

    # if (version->parse( $fromVersion ) < version->parse( '1.1.1' )) {
    #     my $rs = $self->{'db'}->doQuery( 'd', "DELETE FROM domain_dns WHERE owned_by = 'letsencrypt_feature'" );
    #     unless (ref $rs eq 'HASH') {
    #         error( $rs );
    #         return $rs;
    #     }
    # }

    my $rs = $self->_letsencryptInstall();
    $rs ||= $self->_letsencryptConfig( 'configure' );
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
        if ($_->{'status'} =~ /^to(?:add|change)$/) {
            my $rs = $self->_addCertificate( $_->{'domain_id'}, $_->{'cert_name'}, $_->{'alias_id'}, $_->{'subdomain_id'} );
            $rs |= $self->_updateForward(  $_->{'domain_id'}, $_->{'cert_name'}, $_->{'http_forward'} );
            @sql = (
                'UPDATE letsencrypt SET status = ? WHERE letsencrypt_id = ?',
                ($rs ? scalar getMessageByType( 'error' ) || 'Unknown error' : 'ok'), $_->{'letsencrypt_id'}
            );
        } elsif ($_->{'status'} eq 'todelete') {
            my $rs = $self->_deleteCertificate( $_->{'domain_id'}, $_->{'cert_name'}, $_->{'alias_id'}, $_->{'subdomain_id'} );
            $rs |= $self->_updateForward(  $_->{'domain_id'}, $_->{'cert_name'}, 0 );
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
    my ($self, $domainId, $certName, $aliasId, $subdomainId) = @_;
    # This action must be idempotent ( this allow to handle 'tochange' status which include key renewal )

    debug("_addCertificate ");

    # Fake out the SSL_SUPPORT in the Domains module by updating the ssl_certs table and creating a fake cert file
    my $rs = 0;
    my $ssl_cert = $self->{'db'}->doQuery(
        'domain_id', 'SELECT * FROM ssl_certs WHERE domain_type = ? AND domain_id = ?',
        'dmn', $domainId
    );
    if (exists $ssl_cert->{$domainId}) {
        $rs = $self->{'db'}->doQuery(
            'u',
            "UPDATE ssl_certs SET status = 'ok' WHERE domain_type = ? AND domain_id = ? ",
            'dmn', $domainId
        );
    } else {
        $rs = $self->{'db'}->doQuery(
            'i',
            "INSERT INTO ssl_certs (status, domain_type, domain_id) VALUES ('ok', ?, ?)",
            'dmn', $domainId
        );
    }
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    # Create the fake cert file, its not valid PEM but that doesn't matter.
    my $certificate = iMSCP::File->new( filename => "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs/$certName.pem");
    $certificate->set('LetsEncrypt Dummy Certificate');
    $certificate->save();

    # Call certbot-auto to create the key and certificate under /etc/letsencrypt
    my $certbot = $main::imscpConfig{'PLUGINS_DIR'}.'/LetsEncrypt/backend/certbot-auto-test.pm';
    my ($stdout, $stderr);
    # TODO May want to put a check on domain type of 'dmn' before also doing www.$certName CP 2017-08
    execute(
        $certbot . " --no-bootstrap --no-self-update --non-interactive -v -d " . escapeShell($certName) . " -d " . escapeShell('www.' . $certName),
        \$stdout, \$stderr
    ) == 0 or die( $stderr || 'Unknown error' );
    debug( $stdout ) if $stdout;     

    # Trigger an onchange to rebuild the domain, our event listener will then help process the domain config rebuild.
    $self->_triggerDomainOnChange($domainId);
 
    # my $rs = $self->_deleteCertificate( $domainId, $aliasId, $domain );
    # return $rs if $rs;

    0;
}

sub _triggerDomainOnChange
{
    my ($self, $domainId) = @_;

    # Trigger an onchange to rebuild the domain, our event listener will then help process the domain config rebuild.
    my $rs = $self->{'db'}->doQuery(
        'u',
        "UPDATE domain SET domain_status = 'toadd' WHERE domain_id = ? ",
        $domainId
    );
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
    return unless $filename eq 'domain_ssl.tpl';

    my $domain = $data->{'DOMAIN_NAME'};
    my $domain_store_path = '/etc/letsencrypt/live/' . $domain . '/';
    my $key_file = $domain_store_path . $domain . '.key';
    my $cert_file = $domain_store_path . $domain . '.pem';
    my $chain_file = $domain_store_path . $domain . '_chain.pem'; # TODO What is this really? CP 2017-08

    my $snippet = <<EOF;

    SSLEngine On
    SSLCertificateFile _CERTIFICATEFILE_
    SSLCertificateKeyFile _CERTIFICATEKEYFILE_

EOF

    $snippet =~ s/_CERTIFICATEFILE_/$cert_file/g;
    $snippet =~ s/_CERTIFICATEKEYFILE_/$key_file/g;

    $$cfgTpl =~ s/^\s+SSLEngine.*^\n/$snippet/sm;

    0;
}

=item _updateForward($domainId, $certName, $doForward)

 Updates the forward (redirect) status of the domain 'certName' to enable
 either http or the redirect of http -> https for the domain.

 Param int $domainId Domain unique identifier
 Param string $certName Primary name of the target certificate / domain
 Param boolean $doForward True to do the forward / redirect
 Return int 0 on success, other on failure

=cut

sub _updateForward
{
    my ($self, $domainId, $certName, $doForward) = @_;

    # Update the domains table with the forward info
    my $hsts = ($doForward eq '1') ? 'on' : 'off';
    my $rs = $self->{'db'}->doQuery(
        'u',
        "UPDATE ssl_certs SET allow_hsts = ? WHERE domain_id = ? ",
        $hsts, $domainId
    );
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    # This requires a rebuild of the domain, but assume that this is triggered elsewhere

    0;
}

=item _deleteCertificate($domainId, $certName, $aliasId, $domain)

 Removes LetsEncrypt SSL certificate from the domain

 Param int $domainId Domain unique identifier
 Param int $aliasId Domain alias unique identifier (0 if no domain alias)
 Return int 0 on success, other on failure

=cut

sub _deleteCertificate
{
    my ($self, $domainId, $certName, $aliasId, $domain) = @_;

    # Fake out the SSL_SUPPORT in the Domains module by updating the ssl_certs table and creating a fake cert file
    my $rs = 0;
    $rs = $self->{'db'}->doQuery(
        'i',
        "DELETE FROM ssl_certs WHERE domain_type = ? AND domain_id = ?",
        'dmn', $domainId
    );
    unless (ref $rs eq 'HASH') {
        error( $rs );
        return 1;
    }

    # Delete the fake cert file, its not valid PEM but that doesn't matter.
    my $certificate = iMSCP::File->new( filename => "$main::imscpConfig{'GUI_ROOT_DIR'}/data/certs/$certName.pem");
    $certificate->delFile();

    # Trigger an onchange to rebuild the domain, our event listener will then help process the domain config rebuild.
    $self->_triggerDomainOnChange($domainId);
 
    0;
}

=item _letsencryptInstall()

 Install LetsEncrypt software; certbot-auto

 Return int 0 on success, other on failure

=cut

sub _letsencryptInstall
{
    my $file = iMSCP::File->new( filename => '/usr/local/bin/certbot-auto' );
    if (not -e $file->{filename}) {
        execute('wget --no-check-certificate https://dl.eff.org/certbot-auto -P /usr/local/bin/');
    }
    $file->mode(0755);
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
