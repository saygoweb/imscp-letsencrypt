<?php
namespace iMSCP\Plugin\SGW_LetsEncrypt\Test\GraphQL;

/**
 * i-MSCP SGW_LetsEncrypt plugin
 * Copyright (C) 2026 Cambell Prince <cambell.prince@gmail.com>
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

use GraphQL\Type\Schema;
use iMSCP\Database\DatabaseMySQL;
use iMSCP\Plugin\SGW_GraphQL\Api\Container;
use iMSCP\Plugin\SGW_GraphQL\Auth\Scope;
use iMSCP\Plugin\SGW_GraphQL\Extension\ExtensionRegistry;
use iMSCP\Plugin\SGW_GraphQL\Support\GlobalId;
use iMSCP\Plugin\SGW_GraphQL\Support\NodeType;
use iMSCP\Plugin\SGW_GraphQL\Test\Authz\AuthzTestCase;
use iMSCP\Plugin\SGW_LetsEncrypt\GraphQL\LetsEncryptExtension;

/**
 * The SGW_LetsEncrypt extension against the SGW_GraphQL fixture, run as its
 * six accounts - the pattern ExtensionContextTest.php uses for the graphql
 * plugin's own worked example.
 */
class LetsEncryptExtensionTest extends AuthzTestCase
{
    const QUERY = '
        query($id: ID!) {
            node(id: $id) {
                ... on Domain { letsEncrypt { enabled httpForward certName provisioning { state raw settled message } } }
                ... on Subdomain { letsEncrypt { enabled httpForward certName provisioning { state raw settled message } } }
                ... on DomainAlias { letsEncrypt { enabled httpForward certName provisioning { state raw settled message } } }
            }
        }
    ';

    const MUTATION = '
        mutation($id: ID!, $enabled: Boolean!, $httpForward: Boolean) {
            letsEncryptSet(input: { id: $id, enabled: $enabled, httpForward: $httpForward }) {
                name
                ... on Domain { letsEncrypt { enabled httpForward provisioning { state } } }
                ... on Subdomain { letsEncrypt { enabled httpForward provisioning { state } } }
                ... on DomainAlias { letsEncrypt { enabled httpForward provisioning { state } } }
            }
        }
    ';

    public static function setUpBeforeClass(): void
    {
        parent::setUpBeforeClass();
        self::ensureTable();
    }

    /**
     * The plugin's own table may not exist on this box yet. Run its own sql/
     * migrations - never a hand-written copy of the schema - before the
     * fixture opens a transaction: DDL commits it.
     */
    private static function ensureTable(): void
    {
        $pdo = DatabaseMySQL::getPDO();

        if ($pdo->query("SHOW TABLES LIKE 'letsencrypt'")->rowCount() > 0) {
            return;
        }

        $root = dirname(__DIR__, 2);

        foreach (array('001_create_letsencrypt_table.php', '002_letsencrypt_state_text.php') as $file) {
            $migration = require $root . '/sql/' . $file;
            $pdo->exec($migration['up']);
        }
    }

    protected function schema(): Schema
    {
        return $this->container()->schemaFactory()->create();
    }

    private function container(): Container
    {
        $registry = new ExtensionRegistry();
        $registry->register(new LetsEncryptExtension());

        return Container::forTesting(
            // SGW_GraphQL's own root, so it finds its own schema/schema.graphql -
            // not this plugin's directory (this argument names an SGW_GraphQL
            // installation, never the extension's own plugin).
            SGW_GRAPHQL_DIR,
            array(),
            static function (string $sql, array $bind = array()) { return null; },
            static function (int $adminId) { return null; },
            static function (int $adminId) { return true; },
            $this->db,
            (array)\iMSCP\Registry::get('config'),
            $this->core,
            $this->probe,
            $this->sqlServer,
            null,
            null,
            $registry
        );
    }

    private function read(string $tag, int $key, string $who = 'customer'): ?array
    {
        $result = $this->execute(
            self::QUERY, array('id' => GlobalId::encode($tag, $key)), $this->fixture->identity($who)
        );

        self::assertArrayNotHasKey('errors', $result, json_encode($result));

        return $result['data']['node']['letsEncrypt'];
    }

    private function set(
        string $tag, int $key, bool $enabled, $httpForward, string $who, array $scopes = array()
    ): array {
        return $this->execute(
            self::MUTATION,
            array('id' => GlobalId::encode($tag, $key), 'enabled' => $enabled, 'httpForward' => $httpForward),
            $this->fixture->identity($who, $scopes)
        );
    }

    /*
     * -----------------------------------------------------------------
     * The extension is kept and wired the way ExtensionLoader promises.
     * -----------------------------------------------------------------
     */

    public function testTheExtensionIsKeptAndLogsNothing(): void
    {
        $container = $this->container();
        $container->schemaFactory()->create();

        $names = array();
        foreach ($container->extensions() as $extension) {
            $names[] = $extension->getName();
        }

        self::assertSame(array('SGW_LetsEncrypt'), $names);
        self::assertSame(array(), $this->core->logs);
    }

    /*
     * -----------------------------------------------------------------
     * Reads.
     * -----------------------------------------------------------------
     */

    public function testEachVhostKindReadsNullBeforeAnyRowExists(): void
    {
        self::assertNull($this->read(NodeType::DOMAIN, $this->fixture->domainId()));
        self::assertNull($this->read(NodeType::SUBDOMAIN, $this->fixture->subdomainId()));
        self::assertNull($this->read(NodeType::DOMAIN_ALIAS, $this->fixture->aliasId()));
    }

    public function testAnAliasSubdomainAlwaysReadsAsNull(): void
    {
        // The letsencrypt table has no column for one; the fixture's alias
        // subdomain is also still 'toadd', so a real row would show CONFLICT
        // on a write, not null on a read - this is not that case.
        self::assertNull($this->read(NodeType::ALIAS_SUBDOMAIN, $this->fixture->aliasSubdomainId()));
    }

    public function testAFieldOnEachVhostKindReadsWhatWasWritten(): void
    {
        $domainId = $this->fixture->domainId();
        $subdomainId = $this->fixture->subdomainId();
        $aliasId = $this->fixture->aliasId();

        $this->set(NodeType::DOMAIN, $domainId, true, true, 'customer');
        $this->set(NodeType::SUBDOMAIN, $subdomainId, true, false, 'customer');
        $this->set(NodeType::DOMAIN_ALIAS, $aliasId, false, null, 'customer');

        $domain = $this->read(NodeType::DOMAIN, $domainId);
        self::assertSame(
            array('enabled' => false, 'httpForward' => true, 'certName' => $this->fixture->domainName()),
            array('enabled' => $domain['enabled'], 'httpForward' => $domain['httpForward'], 'certName' => $domain['certName'])
        );
        self::assertSame('PENDING', $domain['provisioning']['state']);
        self::assertSame('toadd', $domain['provisioning']['raw']);
        self::assertFalse($domain['provisioning']['settled']);
        self::assertNull($domain['provisioning']['message']);

        $subdomain = $this->read(NodeType::SUBDOMAIN, $subdomainId);
        self::assertFalse($subdomain['httpForward']);
        self::assertSame($this->fixture->subdomainName(), $subdomain['certName']);

        // enabled=false writes 'todelete', which is also PENDING - never 'ok'
        // from this API alone, since nothing here runs the backend.
        $alias = $this->read(NodeType::DOMAIN_ALIAS, $aliasId);
        self::assertSame('PENDING', $alias['provisioning']['state']);
    }

    public function testOneDocumentReadsAllThreeVhostKinds(): void
    {
        $domainId = $this->fixture->domainId();
        $subdomainId = $this->fixture->subdomainId();
        $aliasId = $this->fixture->aliasId();

        $this->set(NodeType::DOMAIN, $domainId, true, false, 'customer');
        $this->set(NodeType::SUBDOMAIN, $subdomainId, true, false, 'customer');
        $this->set(NodeType::DOMAIN_ALIAS, $aliasId, true, false, 'customer');

        $document = '
            query($d: ID!, $s: ID!, $a: ID!) {
                d: node(id: $d) { ... on Domain { letsEncrypt { certName } } }
                s: node(id: $s) { ... on Subdomain { letsEncrypt { certName } } }
                a: node(id: $a) { ... on DomainAlias { letsEncrypt { certName } } }
            }
        ';
        $variables = array(
            'd' => GlobalId::encode(NodeType::DOMAIN, $domainId),
            's' => GlobalId::encode(NodeType::SUBDOMAIN, $subdomainId),
            'a' => GlobalId::encode(NodeType::DOMAIN_ALIAS, $aliasId)
        );

        $result = $this->execute($document, $variables, $this->fixture->identity('customer'));

        self::assertArrayNotHasKey('errors', $result, json_encode($result));
        self::assertSame($this->fixture->domainName(), $result['data']['d']['letsEncrypt']['certName']);
        self::assertSame($this->fixture->subdomainName(), $result['data']['s']['letsEncrypt']['certName']);
        self::assertSame($this->fixture->aliasName(), $result['data']['a']['letsEncrypt']['certName']);
    }

    /**
     * A second vhost of the same kind in the same document must add no more
     * than one query overall - node()'s own per-vhost lookup - and none of
     * it to the letsEncrypt field itself: proof that the field goes through
     * loader()->keyed() rather than one query per vhost (spec section 10.1).
     * Without batching this field, the second vhost would cost two more
     * queries, not one: its own node() lookup, and a second read of the
     * letsencrypt table.
     */
    public function testASecondVhostOfTheSameKindCostsNoMoreQueries(): void
    {
        $domainId = $this->fixture->domainId();
        $siblingDomainId = $this->fixture->siblingDomainId();

        // Both reachable only by the administrator: 'customer' owns the first
        // and 'sibling' the second.
        $this->set(NodeType::DOMAIN, $domainId, true, false, 'admin');
        $this->set(NodeType::DOMAIN, $siblingDomainId, true, false, 'admin');

        $admin = $this->fixture->identity('admin');
        $one = 'query($d: ID!) { d: node(id: $d) { ... on Domain { letsEncrypt { certName } } } }';
        $two = '
            query($d: ID!, $e: ID!) {
                d: node(id: $d) { ... on Domain { letsEncrypt { certName } } }
                e: node(id: $e) { ... on Domain { letsEncrypt { certName } } }
            }
        ';

        $oneCount = $this->db->countQueries(function () use ($one, $domainId, $admin) {
            $result = $this->execute($one, array('d' => GlobalId::encode(NodeType::DOMAIN, $domainId)), $admin);
            self::assertArrayNotHasKey('errors', $result, json_encode($result));
        });

        $twoCount = $this->db->countQueries(function () use ($two, $domainId, $siblingDomainId, $admin) {
            $result = $this->execute(
                $two,
                array(
                    'd' => GlobalId::encode(NodeType::DOMAIN, $domainId),
                    'e' => GlobalId::encode(NodeType::DOMAIN, $siblingDomainId)
                ),
                $admin
            );
            self::assertArrayNotHasKey('errors', $result, json_encode($result));
            self::assertNotNull($result['data']['d']['letsEncrypt']);
            self::assertNotNull($result['data']['e']['letsEncrypt']);
        });

        self::assertLessThanOrEqual($oneCount + 1, $twoCount);
    }

    public function testAFieldAsksForItsScope(): void
    {
        $result = $this->execute(
            self::QUERY,
            array('id' => GlobalId::encode(NodeType::DOMAIN, $this->fixture->domainId())),
            $this->fixture->identity('customer', array(Scope::DOMAINS_WRITE))
        );

        self::assertSame('FORBIDDEN', $result['errors'][0]['extensions']['code'], json_encode($result));
    }

    /*
     * -----------------------------------------------------------------
     * The mutation's happy path, as each of the three roles that may reach it.
     * -----------------------------------------------------------------
     */

    /** @dataProvider mayWrite */
    public function testTheOwnerTheirResellerAndTheAdministratorMayEnableIt(string $who): void
    {
        $result = $this->set(NodeType::SUBDOMAIN, $this->fixture->subdomainId(), true, true, $who);

        self::assertArrayNotHasKey('errors', $result, json_encode($result));
        self::assertSame($this->fixture->subdomainName(), $result['data']['letsEncryptSet']['name']);
        self::assertTrue($result['data']['letsEncryptSet']['letsEncrypt']['enabled'] === false); // still pending
        self::assertSame('PENDING', $result['data']['letsEncryptSet']['letsEncrypt']['provisioning']['state']);
        self::assertSame(1, $this->core->requests);
    }

    public function mayWrite(): array
    {
        return array('customer' => array('customer'), 'reseller' => array('reseller'), 'admin' => array('admin'));
    }

    public function testDisablingWritesTodelete(): void
    {
        $this->set(NodeType::DOMAIN_ALIAS, $this->fixture->aliasId(), true, true, 'customer');
        $this->settle('als', $this->fixture->aliasId());
        $result = $this->set(NodeType::DOMAIN_ALIAS, $this->fixture->aliasId(), false, null, 'customer');

        self::assertArrayNotHasKey('errors', $result, json_encode($result));
        self::assertSame(2, $this->core->requests);

        $row = $this->rowFor('als', $this->fixture->aliasId());
        self::assertSame('todelete', $row['status']);
        // httpForward carried over from the first call, unaffected by the second's null.
        self::assertSame('1', $row['http_forward']);
    }

    public function testOmittingHttpForwardKeepsItsCurrentValue(): void
    {
        $domainId = $this->fixture->domainId();

        $this->set(NodeType::DOMAIN, $domainId, true, true, 'customer');
        $this->settle('dmn', $domainId);
        $this->set(NodeType::DOMAIN, $domainId, true, null, 'customer');

        $row = $this->rowFor('dmn', $domainId);
        self::assertSame('1', $row['http_forward']);
    }

    /*
     * -----------------------------------------------------------------
     * Authorisation, exactly the shape ExtensionContext promises.
     * -----------------------------------------------------------------
     */

    /** @dataProvider mayNotWrite */
    public function testAnybodyElseIsToldTheDomainDoesNotExist(string $who): void
    {
        $result = $this->set(NodeType::DOMAIN, $this->fixture->domainId(), true, null, $who);

        self::assertSame('NOT_FOUND', $result['errors'][0]['extensions']['code'], json_encode($result));
        self::assertSame('input.id', $result['errors'][0]['extensions']['field']);
        self::assertSame(0, $this->core->requests);
    }

    public function mayNotWrite(): array
    {
        return array(
            'sibling'       => array('sibling'),
            'otherCustomer' => array('otherCustomer'),
            'otherReseller' => array('otherReseller')
        );
    }

    public function testAReadOnlyTokenIsForbiddenFromWriting(): void
    {
        $result = $this->set(
            NodeType::DOMAIN, $this->fixture->domainId(), true, null, 'customer', array(Scope::DOMAINS_READ)
        );

        self::assertSame('FORBIDDEN', $result['errors'][0]['extensions']['code'], json_encode($result));
        self::assertSame(0, $this->core->requests);
    }

    /*
     * -----------------------------------------------------------------
     * State: the vhost and the row must both be settled.
     * -----------------------------------------------------------------
     */

    public function testAPendingVhostIsAConflict(): void
    {
        exec_query('UPDATE domain SET domain_status = ? WHERE domain_id = ?', array(
            'toadd', $this->fixture->domainId()
        ));

        $result = $this->set(NodeType::DOMAIN, $this->fixture->domainId(), true, null, 'customer');

        self::assertSame('CONFLICT', $result['errors'][0]['extensions']['code'], json_encode($result));
        self::assertSame(0, $this->core->requests);
    }

    public function testAPendingRowIsAConflict(): void
    {
        $domainId = $this->fixture->domainId();

        $this->set(NodeType::DOMAIN, $domainId, true, null, 'customer');
        self::assertSame(1, $this->core->requests);

        // The row is still 'toadd': nothing here runs the backend to settle it.
        $result = $this->set(NodeType::DOMAIN, $domainId, false, null, 'customer');

        self::assertSame('CONFLICT', $result['errors'][0]['extensions']['code'], json_encode($result));
        self::assertSame(1, $this->core->requests);
    }

    /*
     * -----------------------------------------------------------------
     * The feature gate: an alias subdomain, structurally unsupported.
     * -----------------------------------------------------------------
     */

    public function testAnAliasSubdomainIsFeatureUnavailableOnAWrite(): void
    {
        $result = $this->set(NodeType::ALIAS_SUBDOMAIN, $this->fixture->aliasSubdomainId(), true, null, 'customer');

        self::assertSame('FEATURE_UNAVAILABLE', $result['errors'][0]['extensions']['code'], json_encode($result));
        self::assertSame('letsEncrypt', $result['errors'][0]['extensions']['feature']);
        self::assertSame(0, $this->core->requests);
    }

    /**
     * SGW_LetsEncrypt::customerHasLetsEncrypt() used to hard-code
     * "return true;" (TODO), so this scenario - the customer themselves is
     * not entitled to the feature - could never actually happen; there was
     * nothing for this test to catch. Now that the gate looks at the
     * customer's own admin_status, a suspended (or not yet activated)
     * customer is refused even though they own the vhost and would
     * otherwise pass every earlier check.
     */
    public function testACustomerFailingTheGateGetsFeatureUnavailable(): void
    {
        exec_query(
            'UPDATE admin SET admin_status = ? WHERE admin_id = ?', array('disabled', $this->fixture->customerId())
        );

        $result = $this->set(NodeType::DOMAIN, $this->fixture->domainId(), true, null, 'customer');

        self::assertSame('FEATURE_UNAVAILABLE', $result['errors'][0]['extensions']['code'], json_encode($result));
        self::assertSame('letsEncrypt', $result['errors'][0]['extensions']['feature']);
        self::assertSame(0, $this->core->requests);
    }

    /**
     * The row for one virtual host, read directly - bypassing the API - so a
     * test can check exactly what the mutation wrote.
     */
    private function rowFor(string $kind, int $key): array
    {
        $column = array('dmn' => 'domain_id', 'als' => 'alias_id', 'sub' => 'subdomain_id')[$kind];

        return $this->db->row("SELECT * FROM letsencrypt WHERE $column = ?", array($key));
    }

    /**
     * Stand in for the backend having caught up: this API never runs
     * certbot, so a test that writes twice to the same row must settle it
     * itself in between, or the second write is exactly the CONFLICT
     * testAPendingRowIsAConflict() checks for.
     */
    private function settle(string $kind, int $key): void
    {
        $column = array('dmn' => 'domain_id', 'als' => 'alias_id', 'sub' => 'subdomain_id')[$kind];

        exec_query("UPDATE letsencrypt SET status = 'ok' WHERE $column = ?", array($key));
    }
}
