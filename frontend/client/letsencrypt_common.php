<?php
/**
 * i-MSCP SGW_LetsEncrypt plugin
 * Copyright (C) 2017 Cambell Prince <cambell.prince@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

namespace SGW_LetsEncrypt;

use iMSCP\Database\DatabaseMySQL;
use PDO;

/**
 * The record types listed on the LetsEncrypt page, in the order they are listed
 *
 * The type is part of the identity of a row: domains, aliases and subdomains each number their
 * records from one, so an identifier is only unique within its own type.
 */
const LETSENCRYPT_TYPES = array('domain', 'alias', 'subdomain');

/**
 * Is the backend still expected to act on a domain in the given status?
 *
 * These are the statuses the frontend writes to hand a domain over to the backend. The backend
 * replaces them with 'ok' or 'error' once it has run certbot, which can take tens of seconds.
 *
 * @param string $status
 * @return bool
 */
function letsencrypt_isPending($status)
{
    return in_array(
        $status,
        array('toadd', 'tochange', 'todelete', 'torestore', 'toenable', 'todisable')
    );
}

/**
 * Get the icon class suffix for the given LetsEncrypt status
 *
 * @param string $status
 * @return string
 */
function letsencrypt_statusIcon($status) {
    if ($status == 'ok') {
        return 'ok';
    }
    if ($status == 'disabled') {
        return 'disabled';
    }
    if (letsencrypt_isPending($status)) {
        return 'reload';
    }
    // 'error': the last certbot request for this domain failed, the reason is reported as the note
    return 'error';
}

/**
 * Translate the given LetsEncrypt status
 *
 * @param string $status
 * @return string
 */
function letsencrypt_statusText($status) {
    if ($status == 'error') {
        return tr('Error');
    }
    return translate_dmn_status($status); // TODO Improve the translation for ssl CP 2017-07
}

/**
 * Get the LetsEncrypt state of every record of the given type owned by the given customer
 *
 * The identifier of a row is that of the domain, alias or subdomain record, not that of the
 * letsencrypt record: a domain has no letsencrypt record until it is first edited, and the backend
 * removes the record again once the certificate has been deleted. Both cases read as 'disabled'.
 *
 * @param string $type One of LETSENCRYPT_TYPES
 * @param int $adminId Customer unique identifier
 * @throws \Exception When the type is not a LetsEncrypt record type
 * @return array List of rows, each with the keys type, id, name, http_forward, status and pending
 */
function letsencrypt_fetchRows($type, $adminId)
{
    switch ($type) {
        case 'domain':
            $stmt = exec_query(
                '
                    SELECT domain.domain_id AS id, domain_name AS name, http_forward, status, state
                    FROM domain
                    LEFT JOIN letsencrypt ON (
                        domain.domain_id=letsencrypt.domain_id
                    )
                    WHERE domain_admin_id = ?
                ',
                array($adminId)
            );
            break;
        case 'alias':
            $stmt = exec_query(
                '
                    SELECT domain_aliasses.alias_id AS id, alias_name AS name, http_forward, status, state
                    FROM domain
                    INNER JOIN domain_aliasses ON (domain.domain_id = domain_aliasses.domain_id)
                    LEFT JOIN letsencrypt ON (
                        domain_aliasses.alias_id=letsencrypt.alias_id
                    )
                    WHERE domain_admin_id = ?
                ',
                array($adminId)
            );
            break;
        case 'subdomain':
            $stmt = exec_query(
                '
                    SELECT subdomain.subdomain_id AS id,
                        CONCAT(subdomain_name, \'.\', domain_name) AS name,
                        http_forward, status, state
                    FROM domain
                    INNER JOIN subdomain ON (domain.domain_id = subdomain.domain_id)
                    LEFT JOIN letsencrypt ON (
                        subdomain.subdomain_id=letsencrypt.subdomain_id
                    )
                    WHERE domain_admin_id = ?
                ',
                array($adminId)
            );
            break;
        default:
            throw new \Exception("Unsupported LetsEncrypt type '$type'");
    }

    $rows = array();
    while ($row = $stmt->fetchRow(PDO::FETCH_ASSOC)) {
        $status = $row['status'] ? $row['status'] : 'disabled';
        $rows[] = array(
            'type'         => $type,
            'id'           => intval($row['id']),
            'name'         => decode_idna($row['name']),
            'http_forward' => (bool) $row['http_forward'],
            'status'       => $status,
            'state'        => $row['state'] ? $row['state'] : '',
            'pending'      => letsencrypt_isPending($status)
        );
    }

    return $rows;
}

/**
 * Is the row's status the settled 'ok'?
 *
 * What the client edit page shows as the Enabled checkbox on a fresh GET:
 * true only once the backend has confirmed the certificate, never while a
 * request is still pending or has failed. Shared with the GraphQL extension.
 *
 * @param string $status
 * @return bool
 */
function letsencrypt_isEnabled($status)
{
    return $status === 'ok';
}

/**
 * The letsencrypt row for one virtual host, in the panel's own (domain_type,
 * domain_id) vocabulary - lazily inserted as 'disabled' if none exists yet.
 *
 * The identifier of a row is that of the domain, alias or subdomain record,
 * not that of the letsencrypt record: a domain, alias or subdomain has no
 * letsencrypt record until it is first edited. This is the one place that
 * insert-if-missing rule lives; the client edit page and the GraphQL
 * extension both call it rather than each keeping their own copy.
 *
 * There is no column for an alias subdomain (alssub) - a subdomain_alias row
 * has no representation in this table - so a caller must never pass
 * 'alssub' here; that has to be refused before this is reached.
 *
 * @param string $kind 'dmn', 'als' or 'sub' - the panel's domain_type, minus 'alssub'
 * @param int $key The panel's id in that vhost's own table (domain_id, alias_id or subdomain_id)
 * @param int $ownerId admin_id the vhost must belong to, and the admin_id to record if a row is
 *                     inserted. A caller must always pass the id it has verified owns this vhost -
 *                     $_SESSION['user_id'] on the client pages, or $vhost->getOwnerId() from the
 *                     GraphQL extension's already-authorised target - never an id read back from
 *                     the request unchecked.
 * @throws \Exception For an unsupported $kind
 * @return array|false ['letsencrypt_id', 'cert_name', 'http_forward', 'status', 'state'],
 *                      or false when $kind/$key names no such domain, alias or subdomain owned by
 *                      $ownerId - indistinguishable from a $key that does not exist at all
 */
function letsencrypt_getOrCreateRow($kind, $key, $ownerId)
{
    switch ($kind) {
        case 'dmn':
            $stmt = exec_query(
                '
                    SELECT domain.domain_id AS domain_id, domain_name, letsencrypt_id, cert_name, http_forward, status, state
                    FROM domain
                    LEFT JOIN letsencrypt ON (
                        domain.domain_id=letsencrypt.domain_id
                    )
                    WHERE domain.domain_id = ? AND domain_admin_id = ?
                ',
                array($key, $ownerId)
            );
            break;
        case 'als':
            $stmt = exec_query(
                '
                    SELECT domain_aliasses.alias_id AS alias_id, alias_name, letsencrypt_id, cert_name, http_forward, status, state
                    FROM domain
                    INNER JOIN domain_aliasses ON (domain.domain_id = domain_aliasses.domain_id)
                    LEFT JOIN letsencrypt ON (
                        domain_aliasses.alias_id=letsencrypt.alias_id
                    )
                    WHERE domain_aliasses.alias_id = ? AND domain_admin_id = ?
                ',
                array($key, $ownerId)
            );
            break;
        case 'sub':
            $stmt = exec_query(
                '
                    SELECT subdomain.subdomain_id AS subdomain_id, domain_name, subdomain_name, letsencrypt_id, cert_name, http_forward, status, state
                    FROM domain
                    INNER JOIN subdomain ON (domain.domain_id = subdomain.domain_id)
                    LEFT JOIN letsencrypt ON (
                        subdomain.subdomain_id=letsencrypt.subdomain_id
                    )
                    WHERE subdomain.subdomain_id = ? AND domain_admin_id = ?
                ',
                array($key, $ownerId)
            );
            break;
        default:
            throw new \Exception("Unsupported LetsEncrypt kind '$kind'");
    }

    if (!$stmt->rowCount()) {
        return false;
    }

    $data = $stmt->fetchRow(PDO::FETCH_ASSOC);

    if ($data['letsencrypt_id'] == null) {
        $domain_id = 0;
        $alias_id = null;
        $subdomain_id = null;

        switch ($kind) {
            case 'dmn':
                $certname = $data['domain_name'];
                $domain_id = $key;
                break;
            case 'als':
                $certname = $data['alias_name'];
                $alias_id = $key;
                break;
            case 'sub':
                $certname = $data['subdomain_name'] . '.' . $data['domain_name'];
                $subdomain_id = $key;
                break;
        }

        // Set default values
        $data['cert_name'] = $certname;
        $data['http_forward'] = 0;
        $data['status'] = 'disabled';
        $data['state'] = '';
        exec_query(
            '
                INSERT INTO letsencrypt (
                    admin_id, domain_id, alias_id, subdomain_id, cert_name, http_forward, status, state
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?
                )
            ',
            array($ownerId, $domain_id, $alias_id, $subdomain_id, $data['cert_name'], $data['http_forward'], $data['status'], $data['state'])
        );
        $data['letsencrypt_id'] = DatabaseMySQL::getInstance()->insertId();
    }

    return $data;
}

/**
 * Record an enable/disable/http-forward change and clear any previously
 * recorded failure reason - it no longer describes this request.
 *
 * Shared by the client edit page and the GraphQL extension. Waking the
 * backend (send_request()) is the caller's job, once outside of any
 * transaction (decision D18 in the GraphQL plugin's own vocabulary).
 *
 * @param int $letsencryptId
 * @param bool $enabled
 * @param bool $httpForward
 * @return void
 */
function letsencrypt_applyChange($letsencryptId, $enabled, $httpForward)
{
    exec_query(
        '
            UPDATE letsencrypt
            SET http_forward = ?, status = ?, state = \'\'
            WHERE letsencrypt_id = ?
        ',
        array($httpForward ? 1 : 0, $enabled ? 'toadd' : 'todelete', $letsencryptId)
    );
}
