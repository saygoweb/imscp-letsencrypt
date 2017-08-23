<?php
/**
 * i-MSCP LetsEncrypt plugin
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

namespace LetsEncrypt;

use iMSCP_Events as Events;
use iMSCP_Events_Aggregator as EventManager;
use iMSCP_Plugin_LetsEncrypt as LetsEncrypt;
use iMSCP_pTemplate as TemplateEngine;
use PDO;

/***********************************************************************************************************************
 * Functions
 */

/**
 * Generate page
 *
 * @param $tpl TemplateEngine
 * @return void
 */
function letsencrypt_generatePage($tpl)
{

    //SELECT * FROM `letsencrypt` LEFT JOIN `domain` ON letsencrypt.domain_id = domain.domain_id
    // SELECT letsencrypt_id, cert_name, http_forward, status, state
    // FROM letsencrypt
    // WHERE admin_id = ?
    $stmt = exec_query(
        '
            SELECT domain.domain_id AS domain_id, domain_name, domain_admin_id, http_forward, status, state
            FROM domain LEFT JOIN letsencrypt ON (
                domain.domain_id=letsencrypt.domain_id
            )
            WHERE domain_admin_id = ?
        ',
        array($_SESSION['user_id'])
    );

    if ($stmt->rowCount()) {
        while ($row = $stmt->fetchRow(PDO::FETCH_ASSOC)) {
            if (!$row['status']) {
                $row['status'] = 'disabled';
            }
            if ($row['status'] == 'ok') {
                $statusIcon = 'ok';
            } elseif ($row['status'] == 'disabled') {
                $statusIcon = 'disabled';
            } elseif (in_array(
                $row['status'],
                array('toadd', 'tochange', 'todelete', 'torestore', 'toenable', 'todisable'))
            ) {
                $statusIcon = 'reload';
            } else {
                $statusIcon = 'error';
            }

            $type = 'domain';
            $id = $row['domain_id'];
            $domain_name = decode_idna($row['domain_name']);

            $tpl->assign(array(
                'DOMAIN_NAME'      => decode_idna($row['domain_name']),
                'ID'               => $row['domain_id'],
                'NOTE'             => $row['state'] ? $row['state'] : '',
                'EDIT'             => tr('Edit'),
                'EDIT_LINK'        => 'letsencrypt_edit.php?type=' . $type . '&id=' . $id,
                'STATUS'           => translate_dmn_status($row['status']), // TODO Improve the translation for ssl CP 2017-07
                'STATUS_ICON'      => $statusIcon,
                'HTTP_FORWARD'     => $row['http_forward'] ? tr('yes') : tr('no'),
                'HTTP_FORWRD_ICON' => $row['http_forward'] ? 'check' : '', // TODO
            ));
            $tpl->parse('DOMAINKEY_ITEM', 'domainkey_item'); // TODO
        }
    } else {
        $tpl->assign('CUSTOMER_LIST', '');
        set_page_message(tr('No domain with LetsEncrypt support has been found.'), 'static_info');
    }
}

/***********************************************************************************************************************
 * Main
 */

EventManager::getInstance()->dispatch(Events::onClientScriptStart);
check_login('user');

if (!LetsEncrypt::customerHasLetsEncrypt(intval($_SESSION['user_id']))) {
    showBadRequestErrorPage();
}

$tpl = new TemplateEngine();
$tpl->define_dynamic(array(
    'layout'         => 'shared/layouts/ui.tpl',
    'page'           => '../../plugins/LetsEncrypt/themes/default/view/client/letsencrypt.tpl',
    'page_message'   => 'layout',
    'customer_list'  => 'page',
    'domainkey_item' => 'customer_list'
));
$tpl->assign(array(
    'TR_PAGE_TITLE'   => tr('Customers / LetsEncrypt'),
    'TR_ACTION'       => tr('Actions'),
    'TR_DOMAIN_NAME'  => tr('Domain'),
    'TR_HTTP_FORWARD' => tr('Forward to SSL'),
    'TR_NOTE'         => tr('Notes'),
    'TR_STATUS'       => tr('Status')
));

generateNavigation($tpl);
letsencrypt_generatePage($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
EventManager::getInstance()->dispatch(Events::onClientScriptEnd, array('templateEngine' => $tpl));
$tpl->prnt();

