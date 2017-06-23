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
use iMSCP::Execute;
use iMSCP::File;
use iMSCP::Rights;
use iMSCP::Service;
use iMSCP::TemplateParser;
use Servers::mta;
use version;
use parent 'Common::SingletonClass';

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

    # TODO Find the domains for which we need to generate certificates
    my $rows = $self->{'db'}->doQuery(
        'letsencrypt_id',
        "
            SELECT letsencrypt_id, domain_id, IFNULL(alias_id, 0) AS alias_id, domain_name, letsencrypt_status
            FROM letsencrypt WHERE letsencrypt_status IN('toadd', 'tochange', 'todelete')
        "
    );
    unless (ref $rows eq 'HASH') {
        error( $rows );
        return 1;
    }

    my @sql;
    for(values %{$rows}) {
        if ($_->{'letsencrypt_status'} =~ /^to(?:add|change)$/) {
            my $rs = $self->_addCertificate( $_->{'domain_id'}, $_->{'alias_id'}, $_->{'domain_name'} );
            @sql = (
                'UPDATE letsencrypt SET letsencrypt_status = ? WHERE letsencrypt_id = ?',
                ($rs ? scalar getMessageByType( 'error' ) || 'Unknown error' : 'ok'), $_->{'letsencrypt_id'}
            );
        } elsif ($_->{'letsencrypt_status'} eq 'todelete') {
            my $rs = $self->_deleteCertificate( $_->{'domain_id'}, $_->{'alias_id'}, $_->{'domain_name'} );
            if ($rs) {
                @sql = (
                    'UPDATE letsencrypt SET letsencrypt_status = ? WHERE letsencrypt_id = ?',
                    (scalar getMessageByType( 'error' ) || 'Unknown error'), $_->{'letsencrypt_id'}
                );
            } else {
                @sql = ('DELETE FROM letsencrypt WHERE letsencrypt_id = ?', $_->{'letsencrypt_id'});
            }
        }

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
    $self;
}

=item _addCertificate($domainId, $aliasId, $domain)

 Adds LetsEncrypt SSL certificate to the given domain or alias

 Param int $domainId Domain unique identifier
 Param int $aliasId Domain alias unique identifier ( 0 if no domain alias )
 Param string $domain Domain name
 Return int 0 on success, other on failure

=cut

sub _addCertificate
{
    my ($self, $domainId, $aliasId, $domain) = @_;

    # This action must be idempotent ( this allow to handle 'tochange' status which include key renewal )
 
    # my $rs = $self->_deleteCertificate( $domainId, $aliasId, $domain );
    # return $rs if $rs;

    0;
}

=item _deleteCertificate($domainId, $aliasId, $domain)

 Removes LetsEncrypt SSL certificate from the domain

 Param int $domainId Domain unique identifier
 Param int $aliasId Domain alias unique identifier (0 if no domain alias)
 Return int 0 on success, other on failure

=cut

sub _deleteCertificate
{
    my ($self, $domainId, $aliasId, $domain) = @_;
 
    0;
}

=item _letsencryptInstall()

 Install LetsEncrypt software; certbot-auto

 Return int 0 on success, other on failure

=cut

sub _letsencryptInstall
{
    # TODO :-)
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
