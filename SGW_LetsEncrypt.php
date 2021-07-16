<?php
namespace iMSCP\Plugin\SGW_LetsEncrypt;
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

use iMSCP\Event\Event;
use iMSCP\Event\EventManagerInterface;
use iMSCP\Event\Events;
use iMSCP\Plugin\AbstractPlugin;
use iMSCP\Plugin\PluginException;
use iMSCP\Plugin\PluginManager;
use iMSCP\Registry;

/**
 * Class iMSCP_Plugin_LetsEncrypt
 */
class SGW_LetsEncrypt extends AbstractPlugin
{
    /**
     * Plugin initialization
     *
     * @return void
     */
    public function init()
    {
        l10n_addTranslations(__DIR__ . '/l10n', 'Array', $this->getName());
    }

    /**
     * Register event listeners
     *
     * @param EventManagerInterface $eventsManager
     * @return void
     */
    public function register(EventManagerInterface $eventsManager)
    {
        // TODO Also sub domains? CP 2017-06
        $eventsManager->registerListener(
            array(
                Events::onResellerScriptStart, // Don't think we need this except to enable it at all maybe CP 2017-06
                Events::onClientScriptStart,
                Events::onAfterDeleteDomainAlias, // Cleanup LetsEncrypt for the domain alias
                Events::onAfterDeleteCustomer     // Cleanup LetsEncrypt for this domain / customer
            ),
            $this
        );
    }

    /**
     * Plugin installation
     *
     * @throws PluginException
     * @param PluginManager $pluginManager
     * @return void
     */
    public function install(PluginManager $pluginManager)
    {
        try {
            $this->migrateDb('up');
        } catch (PluginException $e) {
            throw new PluginException($e->getMessage(), $e->getCode(), $e);
        }
    }

    /**
     * Plugin update
     *
     * @throws PluginException When update fail
     * @param PluginManager $pluginManager
     * @param string $fromVersion Version from which plugin update is initiated
     * @param string $toVersion Version to which plugin is updated
     * @return void
     */
    public function update(PluginManager $pluginManager, $fromVersion, $toVersion)
    {
        try {
            $this->migrateDb('up');
            $this->clearTranslations();
            // iMSCP_Registry::get('dbConfig')->del('PORT_LetsEncrypt'); // REVIEW What does this do? CP 2017-06
        } catch (PluginException $e) {
            throw new PluginException($e->getMessage(), $e->getCode(), $e);
        }
    }

    /**
     * Plugin uninstallation
     *
     * @throws PluginException
     * @param PluginManager $pluginManager
     * @return void
     */
    public function uninstall(PluginManager $pluginManager)
    {
        try {
            $this->migrateDb('down');
            $this->clearTranslations();
        } catch (PluginException $e) {
            throw new PluginException($e->getMessage(), $e->getCode(), $e);
        }
    }

    /**
     * onResellerScriptStart event listener
     *
     * @return void
     */
    public function onResellerScriptStart()
    {
        $this->setupNavigation('reseller');
    }

    /**
     * onClientScriptStart event listener
     *
     * @return void
     */
    public function onClientScriptStart()
    {
        // if (self::customerHasLetsEncrypt($_SESSION['user_id'])) { // TODO CP 2017-06
            $this->setupNavigation('client');
        // }
    }

    /**
     * onAfterDeleteCustomer event listener
     *
     * @param Event $event
     * @return void
     */
    public function onAfterDeleteCustomer(Event $event)
    {
        // exec_query(
        //     'UPDATE letsencrypt SET status = ? WHERE customer_id = ?',
        //     array('todelete', $event->getParam('customerId'))
        // );
    }

    /**
     * onAfterDeleteDomainAlias event listener
     *
     * @param Event $event
     * @return void
     */
    public function onAfterDeleteDomainAlias(Event $event)
    {
        exec_query('UPDATE letsencrypt SET status = ? WHERE alias_id = ?', array(
            'todelete', $event->getParam('domainAliasId')
        ));
    }

    /**
     * Get routes
     *
     * @return array
     */
    public function getRoutes()
    {
        $pluginDir = $this->getPluginManager()->pluginGetRootDir() . '/' . $this->getName();
        return array(
            '/reseller/letsencrypt.php'    => $pluginDir . '/frontend/reseller/letsencrypt.php',
            '/client/letsencrypt.php'      => $pluginDir . '/frontend/client/letsencrypt.php',
            '/client/letsencrypt_edit.php' => $pluginDir . '/frontend/client/letsencrypt_edit.php',
            '/client/test.php' => $pluginDir . '/frontend/client/test.php'
        );
    }

    /**
     * Get status of item with errors
     *
     * @return array
     */
    public function getItemWithErrorStatus()
    {
        $stmt = exec_query(
            "
                SELECT letsencrypt_id AS item_id, cert_name AS item_name,
                    'letsencrypt' AS `table`, 'status' AS field
                FROM letsencrypt WHERE status NOT IN(?, ?, ?, ?, ?, ?, ?)
            ",
            array('ok', 'disabled', 'toadd', 'tochange', 'toenable', 'todisable', 'todelete')
        );

        if ($stmt->rowCount()) {
            return $stmt->fetchAll(\PDO::FETCH_ASSOC);
        }

        return array();
    }

    /**
     * Set status of the given plugin item to 'tochange'
     *
     * @param string $table Table name
     * @param string $field Status field name
     * @param int $itemId LetsEncrypt item unique identifier
     * @return void
     */
    public function changeItemStatus($table, $field, $itemId)
    {
        if ($table == 'letsencrypt' && $field == 'status') {
            exec_query('UPDATE letsencrypt SET `status` = ? WHERE letsencrypt_id = ?', array('tochange', $itemId));
        }
    }

    /**
     * Return count of request in progress
     *
     * @return int
     */
    public function getCountRequests()
    {
        $stmt = exec_query(
            'SELECT COUNT(letsencrypt_id) AS cnt FROM letsencrypt WHERE `status` IN (?, ?, ?, ?, ?)',
            array('toadd', 'tochange', 'toenable', 'todisable', 'todelete')
        );

        $row = $stmt->fetchRow(\PDO::FETCH_ASSOC);

        return $row['cnt'];
    }

    /**
     * Does the given customer has LetsEncrypt feature activated?
     *
     * @param int $customerId Customer unique identifier
     * @return bool
     */
    public static function customerHasLetsEncrypt($customerId)
    {
        static $hasAccess = NULL;

        return true; // TODO Currently everyone has LetsEncrypt available on their account.

        // if (NULL === $hasAccess) {
        //     $stmt = exec_query(
        //         '
        //             SELECT COUNT(admin_id) as cnt FROM letsencrypt INNER JOIN admin USING(admin_id)
        //             WHERE admin_id = ? AND admin_status = ?
        //         ',
        //         array($customerId, 'ok')
        //     );

        //     $row = $stmt->fetchRow(PDO::FETCH_ASSOC);
        //     $hasAccess = (bool)$row['cnt'];
        // }

        // return $hasAccess;
    }

    /**
     * Inject LetsEncrypt links into the navigation object
     *
     * @param string $level UI level
     */
    protected function setupNavigation($level)
    {
        if (Registry::isRegistered('navigation')) {
            /** @var Zend_Navigation $navigation */
            $navigation = Registry::get('navigation');

            if ($level == 'reseller') {
                if (($page = $navigation->findOneBy('uri', '/reseller/users.php'))) {
                    $page->addPage(array(
                        'label'              => tr('LetsEncrypt'),
                        'uri'                => '/reseller/letsencrypt.php',
                        'title_class'        => 'users',
                        'privilege_callback' => array(
                            'name' => 'resellerHasCustomers'
                        )
                    ));
                }
            } elseif ($level == 'client') {
                if (($page = $navigation->findOneBy('uri', '/client/domains_manage.php'))) {
                    $page->addPage(array(
                        'label'       => tr('LetsEncrypt'),
                        'uri'         => '/client/letsencrypt.php',
                        'title_class' => 'domains',
                        'pages'       => array(
                            'letsencrypt_edit' => array(
                                'label'       => tr('LetsEncrypt Edit'),
                                'uri'         => '/client/letsencrypt_edit.php',
                                'title_class' => ''
                            )
                        )
                    ));
                }
            }
        }
    }

    /**
     * Clear translations if any
     *
     * @return void
     */
    protected function clearTranslations()
    {
        /** @var Zend_Translate $translator */
        $translator = Registry::get('translator');

        if ($translator->hasCache()) {
            $translator->clearCache($this->getName());
        }
    }
}
