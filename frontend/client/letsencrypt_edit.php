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
use iMSCP\Event\EventAggregator;
use iMSCP\Event\Events;
use iMSCP\Plugin\SGW_LetsEncrypt\SGW_LetsEncrypt;
use iMSCP\TemplateEngine;
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

    switch ($type) {
        case 'domain':
            $stmt = exec_query(
                '
                    SELECT domain.domain_id AS domain_id, domain_name, domain_admin_id, letsencrypt_id, cert_name, http_forward, status, state
                    FROM domain
                    LEFT JOIN letsencrypt ON (
                        domain.domain_id=letsencrypt.domain_id
                    )
                    WHERE domain.domain_id = ?
                ',
                array($id)
            );
            break;
        case 'alias':
    //     '
    //     SELECT domain_aliasses.alias_id AS alias_id, alias_name, domain_admin_id, http_forward, status, state
    //     FROM domain
    //     INNER JOIN domain_aliasses ON (domain.domain_id = domain_aliasses.domain_id)
    //     LEFT JOIN letsencrypt ON (
    //         domain_aliasses.alias_id=letsencrypt.alias_id
    //     )
    //     WHERE domain_admin_id = ?
    // ',
    // array($_SESSION['user_id'])
            $stmt = exec_query(
                '
                    SELECT domain_aliasses.alias_id AS alias_id, alias_name, domain_admin_id, letsencrypt_id, cert_name, http_forward, status, state
                    FROM domain
                    INNER JOIN domain_aliasses ON (domain.domain_id = domain_aliasses.domain_id)
                    LEFT JOIN letsencrypt ON (
                        domain_aliasses.alias_id=letsencrypt.alias_id
                    )
                    WHERE domain_aliasses.alias_id = ?
                ',
                array($id)
            );
            break;
        case 'subdomain':
    //     '
    //     SELECT subdomain.subdomain_id AS subdomain_id, subdomain_name, domain_name, domain_admin_id, http_forward, status, state
    //     FROM domain
    //     INNER JOIN subdomain ON (domain.domain_id = subdomain.domain_id)
    //     LEFT JOIN letsencrypt ON (
    //         subdomain.subdomain_id=letsencrypt.subdomain_id
    //     )
    //     WHERE domain_admin_id = ?
    // ',
            $stmt = exec_query(
                '
                    SELECT subdomain.subdomain_id AS subdomain_id, domain_name, subdomain_name, domain_admin_id, letsencrypt_id, cert_name, http_forward, status, state
                    FROM domain
                    INNER JOIN subdomain ON (domain.domain_id = subdomain.domain_id)
                    LEFT JOIN letsencrypt ON (
                        subdomain.subdomain_id=letsencrypt.subdomain_id
                    )
                    WHERE subdomain.subdomain_id = ?
                ',
                array($id)
            );
            break;
        default:
            return false;
    }

    if (!$stmt->rowCount()) {
        return false;
    }

    $data = $stmt->fetchRow(PDO::FETCH_ASSOC);
    if ($data['letsencrypt_id'] == null) {
        $db = DatabaseMySQL::getInstance();

        $domain_id = 0;
        $alias_id = null;
        $subdomain_id = null;
        switch ($type) {
            case 'domain':
                $certname = $data['domain_name'];
                $domain_id = $id;
                break;
            case 'alias':
                $certname = $data['alias_name'];
                $alias_id = $id;
                break;
            case 'subdomain':
                $certname = $data['subdomain_name'] . '.' . $data['domain_name'];
                $subdomain_id = $id;
                break;
            default:
                throw new \Exception("Unsupported LetsEncrypt type '$type'");
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
            array($_SESSION['user_id'], $domain_id, $alias_id, $subdomain_id, $data['cert_name'], $data['http_forward'], $data['status'], $data['state'])
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

