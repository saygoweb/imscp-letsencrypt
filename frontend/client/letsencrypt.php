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

use iMSCP\Event\EventAggregator;
use iMSCP\Event\Events;
use iMSCP\Plugin\SGW_LetsEncrypt\SGW_LetsEncrypt;
use iMSCP\TemplateEngine;

require_once __DIR__ . '/letsencrypt_common.php';

/***********************************************************************************************************************
 * Functions
 */

/**
 * Assign a single domain, alias or subdomain to the current template block
 *
 * @param $tpl TemplateEngine
 * @param array $row Row as returned by letsencrypt_fetchRows()
 * @return void
 */
function letsencrypt_assignRow($tpl, $row)
{
    $tpl->assign(array(
        'DOMAIN_NAME'      => tohtml($row['name']),
        'ID'               => $row['id'],
        'NOTE'             => tohtml($row['state']),
        'EDIT'             => tr('Edit'),
        'EDIT_LINK'        => 'letsencrypt_edit.php?type=' . $row['type'] . '&id=' . $row['id'],
        'STATUS'           => letsencrypt_statusText($row['status']),
        'STATUS_ICON'      => letsencrypt_statusIcon($row['status']),
        // Marks the rows the backend still has to act on, so that the page only starts polling
        // letsencrypt_status.php when there is something to wait for
        'PENDING'          => $row['pending'] ? ' data-le-pending' : '',
        'HTTP_FORWARD'     => $row['http_forward'] ? tr('yes') : tr('no'),
        'HTTP_FORWRD_ICON' => $row['http_forward'] ? 'check' : '', // TODO
    ));
}

/**
 * Generate domains
 *
 * @param $tpl TemplateEngine
 * @return void
 */
function letsencrypt_generateDomains($tpl)
{
    foreach (letsencrypt_fetchRows('domain', $_SESSION['user_id']) as $row) {
        letsencrypt_assignRow($tpl, $row);
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
    $rows = letsencrypt_fetchRows('alias', $_SESSION['user_id']);

    if (!count($rows)) {
        $tpl->assign(array(
            'ALS_MSG' => tr('You do not have domain aliases.'),
            'ALS_LIST' => ''
        ));
        return;
    }

    foreach ($rows as $row) {
        letsencrypt_assignRow($tpl, $row);
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
    $rows = letsencrypt_fetchRows('subdomain', $_SESSION['user_id']);

    if (!count($rows)) {
        $tpl->assign(array(
            'SUB_MSG' => tr('You do not have subdomains.'),
            'SUB_LIST' => ''
        ));
        return;
    }

    foreach ($rows as $row) {
        letsencrypt_assignRow($tpl, $row);
        $tpl->parse('SUB_ITEM', '.sub_item'); // TODO
    }
    $tpl->assign('SUB_MESSAGE', '');
}

/***********************************************************************************************************************
 * Main
 */
EventAggregator::getInstance()->dispatch(Events::onClientScriptStart);
check_login('user');

if (!SGW_LetsEncrypt::customerHasLetsEncrypt(intval($_SESSION['user_id']))) {
    showBadRequestErrorPage();
}

$tpl = new TemplateEngine();
$tpl->define_dynamic(array(
    'layout'                     => 'shared/layouts/ui.tpl',
    'page'                       => '../../plugins/SGW_LetsEncrypt/themes/default/view/client/letsencrypt.tpl',
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
EventAggregator::getInstance()->dispatch(Events::onClientScriptEnd, array('templateEngine' => $tpl));
$tpl->prnt();

