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
 * Get letsencrypt data
 *
 * A thin translation of this page's own vocabulary ('domain', 'alias',
 * 'subdomain') onto the panel's (dmn/als/sub), memoised for the request:
 * this is called once by letsencrypt_edit_generatePage() and, on a POST,
 * once more by client_editLetsEncrypt() first. The actual lookup-or-insert
 * rule lives in letsencrypt_getOrCreateRow(), shared with the GraphQL
 * extension.
 *
 * @access private
 * @param string $type type of record identifier 'domain', 'subdomain', or 'alias'
 * @param int $id record identifier
 * @return array|bool LetsEncrypt data or false on error
 */
function _client_getEditData($type, $id)
{
    static $data = NULL;

    if (NULL !== $data) {
        return $data;
    }

    $kinds = array('domain' => 'dmn', 'alias' => 'als', 'subdomain' => 'sub');

    if (!isset($kinds[$type])) {
        return false;
    }

    $data = letsencrypt_getOrCreateRow($kinds[$type], $id, intval($_SESSION['user_id']));

    return $data;
}

/**
 * Generate page
 *
 * @param $tpl iMSCP_pTemplate
 * @return void
 */
function letsencrypt_edit_generatePage($tpl)
{
    if (!isset($_GET['type']) || !isset($_GET['id'])) {
        showBadRequestErrorPage();
    }

    $type = $_GET['type'];
    $id = intval($_GET['id']);
    $data = _client_getEditData($type, $id);

    if ($data === false) {
        showBadRequestErrorPage();
    }

    if (empty($_POST)) {
        $enabled = $data['status'] === 'ok';
        $http_forward = $data['http_forward'] == 1;
    } else {
        $enabled = (isset($_POST['enabled']) && $_POST['enabled'] == 'yes') ? true : false;
        $http_forward = (isset($_POST['http_forward']) && $_POST['http_forward'] == 'yes') ? true : false;
    }

    $tpl->assign(array(
        'TYPE'               => $type,
        'ID'                 => $id,
        'DOMAIN_NAME'        => tohtml($data['cert_name']),
        'ENABLED_YES'        => ($enabled) ? ' checked' : '',
        'ENABLED_NO'         => ($enabled) ? '' : ' checked',
        'HTTP_FORWARD_YES'   => ($http_forward) ? ' checked' : '',
        'HTTP_FORWARD_NO'    => ($http_forward) ? '' : ' checked',
    ));

}

/**
 * Edit domain
 *
 * @return bool TRUE on success, FALSE on failure
 */
function client_editLetsEncrypt()
{
   if (!isset($_GET['type']) || !isset($_GET['id'])) {
        showBadRequestErrorPage();
    }

    $type = $_GET['type'];
    $id = intval($_GET['id']);
    $data = _client_getEditData($type, $id);

    if ($data === false) {
        showBadRequestErrorPage();
    }

    $enabled = $_POST['enabled'] == 'yes';
    $http_forward = $_POST['http_forward'] == 'yes';

    letsencrypt_applyChange($data['letsencrypt_id'], $enabled, $http_forward);

    send_request();
    write_log(sprintf('%s updated properties of the %s domain', $_SESSION['user_logged'], $data['domain_name_utf8']), E_USER_NOTICE);
    return true;
}

/***********************************************************************************************************************
 * Main
 */

EventAggregator::getInstance()->dispatch(Events::onClientScriptStart);
check_login('user');

if (!SGW_LetsEncrypt::customerHasLetsEncrypt(intval($_SESSION['user_id']))) {
    showBadRequestErrorPage();
}

if (!empty($_POST) && client_editLetsEncrypt()) {
    set_page_message(tr('Domain successfully scheduled for update.'), 'success');
    redirectTo('letsencrypt.php');
}

$tpl = new TemplateEngine();
$tpl->define_dynamic(array(
    'layout'             => 'shared/layouts/ui.tpl',
    'page'               => '../../plugins/SGW_LetsEncrypt/themes/default/view/client/letsencrypt_edit.tpl',
    'page_message'       => 'layout'
));
$tpl->assign(array(
    'TR_PAGE_TITLE'             => tr('Client / Domains / Edit Domain'),
    'TR_YES'                    => tr('Yes'),
    'TR_NO'                     => tr('No'),
    'TR_UPDATE'                 => tr('Update'),
    'TR_CANCEL'                 => tr('Cancel'),
    'TR_DOMAIN'                 => tr('Domain'),
    'TR_DOMAIN_NAME'            => tr('Domain name'),
    'TR_ENABLED'                => tr('Enabled'),
    'TR_ENABLED_TOOLTIP'        => tr("Enabled tooltip"),
    'TR_HTTP_FORWARD'           => tr('Redirect HTTP'),
    'TR_HTTP_FORWARD_TOOLTIP'   => tr("Redirect HTTP tooltip"),
));

// EventManager::getInstance()->registerListener('onGetJsTranslations', function ($e) {
//     /** @var $e iMSCP_Events_Event */
//     $translations = $e->getParam('translations');
//     $translations['core']['close'] = tr('Close');
//     $translations['core']['ftp_directories'] = tr('Select your own document root');
// });
generateNavigation($tpl);
letsencrypt_edit_generatePage($tpl);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
EventAggregator::getInstance()->dispatch(Events::onClientScriptEnd, array('templateEngine' => $tpl));
$tpl->prnt();

