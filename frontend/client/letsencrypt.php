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
    $stmt = exec_query(
        '
            SELECT letsencrypt_id, domain_name, letsencrypt_status, domain_dns, domain_text
            FROM letsencrypt LEFT JOIN domain_dns ON(
                domain_dns.domain_id = letsencrypt.domain_id
                AND domain_dns.alias_id = IFNULL(letsencrypt.alias_id, 0) AND owned_by = ?
            ) WHERE admin_id = ?
        ',
        array('LetsEncrypt_Plugin', $_SESSION['user_id'])
    );

    if ($stmt->rowCount()) {
        while ($row = $stmt->fetchRow(PDO::FETCH_ASSOC)) {
            if ($row['letsencrypt_status'] == 'ok') {
                $statusIcon = 'ok';
            } elseif ($row['letsencrypt_status'] == 'disabled') {
                $statusIcon = 'disabled';
            } elseif (in_array(
                $row['letsencrypt_status'],
                array('toadd', 'tochange', 'todelete', 'torestore', 'tochange', 'toenable', 'todisable', 'todelete'))
            ) {
                $statusIcon = 'reload';
            } else {
                $statusIcon = 'error';
            }

            if ($row['domain_text']) {
                if (strpos($row['domain_dns'], ' ') !== false) {
                    $dnsName = explode(' ', $row['domain_dns']);
                    $dnsName = $dnsName[0];
                } else {
                    $dnsName = $row['domain_dns'];
                }
            } else {
                $dnsName = '';
            }

            $tpl->assign(array(
                'DOMAIN_NAME' => decode_idna($row['domain_name']),
                'DOMAIN_KEY'  => ($row['domain_text']) ? tohtml($row['domain_text']) : tr('Generation in progress.'),
                'LETSENCRYPT_ID' => $row['letsencrypt_id'],
                'DNS_NAME'    => ($dnsName) ? tohtml($dnsName) : tr('n/a'),
                'STATUS'  => translate_dmn_status($row['letsencrypt_status']),
                'STATUS_ICON' => $statusIcon
            ));
            $tpl->parse('DOMAINKEY_ITEM', '.domainkey_item');
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
    'TR_PAGE_TITLE'  => tr('Customers / LetsEncrypt'),
    'TR_DOMAIN_NAME' => tr('Domain'),
    'TR_NOTE'        => tr('Notes'),
    'TR_ENABLED'     => tr('Enabled'),
    'TR_STATUS'      => tr('Status')
));

generateNavigation($tpl);
letsencrypt_generatePage($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
EventManager::getInstance()->dispatch(Events::onClientScriptEnd, array('templateEngine' => $tpl));
$tpl->prnt();

