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

use iMSCP\Plugin\SGW_LetsEncrypt\SGW_LetsEncrypt;

require_once __DIR__ . '/letsencrypt_common.php';

/**
 * Requesting a certificate takes tens of seconds, during which the domain sits in a 'to...' status
 * waiting for the backend. This endpoint reports the current status of every domain of the logged
 * in customer so that letsencrypt.php can update its table without a page reload.
 *
 * The status text and icon are resolved here rather than in the browser so that the polled rows and
 * the rows rendered by letsencrypt.php cannot disagree, and so that the translations stay in PHP.
 */

/***********************************************************************************************************************
 * Main
 */
check_login('user');

// The endpoint answers XHR only. Requiring the header also means a cross origin page cannot reach
// it without a CORS preflight that we never answer.
if (!is_xhr()) {
    showBadRequestErrorPage();
}

if (!SGW_LetsEncrypt::customerHasLetsEncrypt(intval($_SESSION['user_id']))) {
    showBadRequestErrorPage();
}

$rows = array();
$pending = false;

foreach (LETSENCRYPT_TYPES as $type) {
    foreach (letsencrypt_fetchRows($type, $_SESSION['user_id']) as $row) {
        $pending = $pending || $row['pending'];
        $rows[] = array(
            'type'        => $row['type'],
            'id'          => $row['id'],
            'status'      => letsencrypt_statusText($row['status']),
            'icon'        => letsencrypt_statusIcon($row['status']),
            'note'        => $row['state'],
            'httpForward' => $row['http_forward'] ? tr('yes') : tr('no'),
            'pending'     => $row['pending']
        );
    }
}

// Values are inserted as text by the browser, so they are sent unescaped
header('Content-Type: application/json');
echo json_encode(array('pending' => $pending, 'rows' => $rows));
return;
