<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 * Copyright (C) 2010-2017 by i-MSCP Team
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
use iMSCP_Database;
use PDO;

/***********************************************************************************************************************
 * Functions
 */

/**
 * Get letsencrypt data
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

    if ($type == 'domain') {
        $stmt = exec_query(
            '
                SELECT domain.domain_id AS domain_id, domain_name, domain_admin_id, letsencrypt_id, cert_name, http_forward, status, state
                FROM domain LEFT JOIN letsencrypt ON (
                    domain.domain_id=letsencrypt.domain_id
                )
                WHERE domain.domain_id = ?
            ',
            array($id)
        );
    } else {
        return false;
    }

    if (!$stmt->rowCount()) {
        return false;
    }

    $data = $stmt->fetchRow(PDO::FETCH_ASSOC);
    if ($data['letsencrypt_id'] == null) {
        $db = iMSCP_Database::getInstance();

        // Set default values
        $data['cert_name'] = $data['domain_name'];
        $data['http_forward'] = 0;
        $data['status'] = 'disabled';
        $data['state'] = '';
        exec_query(
            '
                INSERT INTO letsencrypt (
                    admin_id, domain_id, cert_name, http_forward, status, state
                ) VALUES (
                    ?, ?, ?, ?, ?, ?
                )
            ',
            array($_SESSION['user_id'], $data['domain_id'], $data['cert_name'], $data['http_forward'], $data['status'], $data['state'])
        );
        $data['letsencrypt_id'] = $db->insertId();
    }

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

    $status = $_POST['enabled'] == 'yes' ? 'toadd' : 'todelete';
    $http_forward = $_POST['http_forward'] == 'yes' ? 1 : 0;

    exec_query(
        '
            UPDATE letsencrypt
            SET http_forward = ?, status = ?
            WHERE letsencrypt_id = ?
        ',
        array($http_forward, $status, $data['letsencrypt_id'])
    );

    send_request();
    write_log(sprintf('%s updated properties of the %s domain', $_SESSION['user_logged'], $data['domain_name_utf8']), E_USER_NOTICE);
    return true;
}

/***********************************************************************************************************************
 * Main
 */

EventManager::getInstance()->dispatch(Events::onClientScriptStart);
check_login('user');

if (!LetsEncrypt::customerHasLetsEncrypt(intval($_SESSION['user_id']))) {
    showBadRequestErrorPage();
}

if (!empty($_POST) && client_editLetsEncrypt()) {
    set_page_message(tr('Domain successfully scheduled for update.'), 'success');
    redirectTo('letsencrypt.php');
}

$tpl = new TemplateEngine();
$tpl->define_dynamic(array(
    'layout'             => 'shared/layouts/ui.tpl',
    'page'               => '../../plugins/LetsEncrypt/themes/default/view/client/letsencrypt_edit.tpl',
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
EventManager::getInstance()->dispatch(Events::onClientScriptEnd, array('templateEngine' => $tpl));
$tpl->prnt();

