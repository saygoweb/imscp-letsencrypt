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

function letsencrypt_statusIcon($status) {
    $statusIcon = 'error';
    if ($status == 'ok') {
        $statusIcon = 'ok';
    } elseif ($status == 'disabled') {
        $statusIcon = 'disabled';
    } elseif (in_array(
        $status,
        array('toadd', 'tochange', 'todelete', 'torestore', 'toenable', 'todisable'))
    ) {
        $statusIcon = 'reload';
    }
    return $statusIcon;
}

/**
 * Generate domains
 *
 * @param $tpl TemplateEngine
 * @return void
 */
function letsencrypt_generateDomains($tpl)
{
    $stmt = exec_query(
        '
            SELECT domain.domain_id AS domain_id, domain_name, domain_admin_id, http_forward, status, state
            FROM domain
            LEFT JOIN letsencrypt ON (
                domain.domain_id=letsencrypt.domain_id
            )
            WHERE domain_admin_id = ?
        ',
        array($_SESSION['user_id'])
    );

    while ($row = $stmt->fetchRow(PDO::FETCH_ASSOC)) {
        if (!$row['status']) {
            $row['status'] = 'disabled';
        }
        $statusIcon = letsencrypt_statusIcon($row['status']);
        $type = 'domain';
        $id = $row['domain_id'];

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
        $tpl->parse('DOMAIN_ITEM', '.domain_item'); // TODO
    }
}

/**
 * Generate aliases
 *
 * @param $tpl TemplateEngine
 * @return void
 */
 function letsencrypt_generateAliases($tpl)
 {
     $stmt = exec_query(
         '
             SELECT domain_aliasses.alias_id AS alias_id, alias_name, domain_admin_id, http_forward, status, state
             FROM domain
             INNER JOIN domain_aliasses ON (domain.domain_id = domain_aliasses.domain_id)
             LEFT JOIN letsencrypt ON (
                 domain_aliasses.alias_id=letsencrypt.alias_id
             )
             WHERE domain_admin_id = ?
         ',
         array($_SESSION['user_id'])
     );
 
    if (!$stmt->rowCount()) {
        $tpl->assign(array(
            'ALS_MSG' => tr('You do not have domain aliases.'),
            'ALS_LIST' => ''
        ));
        return;
    }

    while ($row = $stmt->fetchRow(PDO::FETCH_ASSOC)) {
        if (!$row['status']) {
            $row['status'] = 'disabled';
        }
        $statusIcon = letsencrypt_statusIcon($row['status']);
        $type = 'alias';
        $id = $row['alias_id'];

        $tpl->assign(array(
            'DOMAIN_NAME'      => decode_idna($row['alias_name']),
            'ID'               => $row['alias_id'],
            'NOTE'             => $row['state'] ? $row['state'] : '',
            'EDIT'             => tr('Edit'),
            'EDIT_LINK'        => 'letsencrypt_edit.php?type=' . $type . '&id=' . $id,
            'STATUS'           => translate_dmn_status($row['status']), // TODO Improve the translation for ssl CP 2017-07
            'STATUS_ICON'      => $statusIcon,
            'HTTP_FORWARD'     => $row['http_forward'] ? tr('yes') : tr('no'),
            'HTTP_FORWRD_ICON' => $row['http_forward'] ? 'check' : '', // TODO
        ));
        $tpl->parse('ALS_ITEM', '.als_item'); // TODO
    }
    $tpl->assign('ALS_MESSAGE', '');
 }
 
/**
 * Generate subdomains
 *
 * @param $tpl TemplateEngine
 * @return void
 */
 function letsencrypt_generateSubdomains($tpl)
 {
     $stmt = exec_query(
         '
             SELECT subdomain.subdomain_id AS subdomain_id, subdomain_name, domain_name, domain_admin_id, http_forward, status, state
             FROM domain
             INNER JOIN subdomain ON (domain.domain_id = subdomain.domain_id)
             LEFT JOIN letsencrypt ON (
                 subdomain.subdomain_id=letsencrypt.subdomain_id
             )
             WHERE domain_admin_id = ?
         ',
         array($_SESSION['user_id'])
     );
 
    if (!$stmt->rowCount()) {
        $tpl->assign(array(
            'SUB_MSG' => tr('You do not have subdomains.'),
            'SUB_LIST' => ''
        ));
        return;
    }

    while ($row = $stmt->fetchRow(PDO::FETCH_ASSOC)) {
        if (!$row['status']) {
            $row['status'] = 'disabled';
        }
        $statusIcon = letsencrypt_statusIcon($row['status']);
        $type = 'subdomain';
        $id = $row['subdomain_id'];

        $tpl->assign(array(
            'DOMAIN_NAME'      => decode_idna($row['subdomain_name'] . '.' . $row['domain_name']),
            'ID'               => $row['subdomain_id'],
            'NOTE'             => $row['state'] ? $row['state'] : '',
            'EDIT'             => tr('Edit'),
            'EDIT_LINK'        => 'letsencrypt_edit.php?type=' . $type . '&id=' . $id,
            'STATUS'           => translate_dmn_status($row['status']), // TODO Improve the translation for ssl CP 2017-07
            'STATUS_ICON'      => $statusIcon,
            'HTTP_FORWARD'     => $row['http_forward'] ? tr('yes') : tr('no'),
            'HTTP_FORWRD_ICON' => $row['http_forward'] ? 'check' : '', // TODO
        ));
        $tpl->parse('SUB_ITEM', '.sub_item'); // TODO
    }
    $tpl->assign('SUB_MESSAGE', '');
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
    'layout'                     => 'shared/layouts/ui.tpl',
    'page'                       => '../../plugins/LetsEncrypt/themes/default/view/client/letsencrypt.tpl',
    'page_message'               => 'layout',
    'domain_list'                => 'page',
    'domain_item'                => 'domain_list',
    'domain_status_reload_true'  => 'domain_item',
    'domain_status_reload_false' => 'domain_item',
    'domain_aliases_block'       => 'page',
    'als_message'                => 'domain_aliases_block',
    'als_list'                   => 'domain_aliases_block',
    'als_item'                   => 'als_list',
    'als_status_reload_true'     => 'als_item',
    'als_status_reload_false'    => 'als_item',
    'subdomains_block'           => 'page',
    'sub_message'                => 'subdomains_block',
    'sub_list'                   => 'subdomains_block',
    'sub_item'                   => 'sub_list',
));
$tpl->assign(array(
    'TR_PAGE_TITLE'     => tr('Customers / LetsEncrypt'),
    'TR_ACTION'         => tr('Actions'),
    'TR_DOMAINS'        => tr('Domains'),
    'TR_DOMAIN_ALIASES' => tr('Aliases'),
    'TR_SUBDOMAINS'     => tr('Subdomains'),
    'TR_DOMAIN_NAME'    => tr('Domain'),
    'TR_HTTP_FORWARD'   => tr('Forward to SSL'),
    'TR_NOTE'           => tr('Notes'),
    'TR_STATUS'         => tr('Status')
));

generateNavigation($tpl);
letsencrypt_generateDomains($tpl);
letsencrypt_generateAliases($tpl);
letsencrypt_generateSubdomains($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
EventManager::getInstance()->dispatch(Events::onClientScriptEnd, array('templateEngine' => $tpl));
$tpl->prnt();

