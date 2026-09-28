<?php
namespace iMSCP\Plugin\SGW_LetsEncrypt\GraphQL;

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

use iMSCP\Plugin\SGW_GraphQL\Auth\Scope;
use iMSCP\Plugin\SGW_GraphQL\Extension\Extension;
use iMSCP\Plugin\SGW_GraphQL\Extension\ExtensionContext;
use iMSCP\Plugin\SGW_GraphQL\Security\Guard;
use iMSCP\Plugin\SGW_GraphQL\Support\Provisioning;
use iMSCP\Plugin\SGW_LetsEncrypt\SGW_LetsEncrypt;

use function SGW_LetsEncrypt\letsencrypt_applyChange;
use function SGW_LetsEncrypt\letsencrypt_getOrCreateRow;
use function SGW_LetsEncrypt\letsencrypt_isEnabled;

// The plain functions this extension reuses rather than duplicates. Not
// autoloaded - they are page script functions, not a class - so this is the
// one place outside the client pages that pulls them in.
require_once __DIR__ . '/../frontend/client/letsencrypt_common.php';

/**
 * Exposes the plugin's per-vhost Let's Encrypt setting over GraphQL: a field
 * to read it and a mutation to change it, on top of whatever
 * letsencrypt_common.php and letsencrypt_edit.php's own reusable functions
 * already do for the client pages.
 *
 * The letsencrypt table has no column for an alias subdomain (alssub) - it
 * only ever tracks a domain_id, an alias_id or a subdomain_id - so this
 * extension refuses one rather than guessing which column it might mean:
 * null on a read, FEATURE_UNAVAILABLE on a write.
 */
final class LetsEncryptExtension implements Extension
{
    public function getName(): string
    {
        return 'SGW_LetsEncrypt';
    }

    public function getSdl(): string
    {
        return '
            type LetsEncryptSetting {
              "Whether a certificate is requested for this site (or, once settled, already issued)."
              enabled: Boolean!
              "Whether HTTP traffic is redirected to HTTPS."
              httpForward: Boolean!
              "The name certbot was asked to certify."
              certName: String!
              """
              Whether the backend has caught up with the last change.
              The certbot failure reason, when there is one, is carried as message.
              """
              provisioning: Provisioning!
            }

            extend type Domain { letsEncrypt: LetsEncryptSetting }
            extend type Subdomain { letsEncrypt: LetsEncryptSetting }
            extend type DomainAlias { letsEncrypt: LetsEncryptSetting }

            input LetsEncryptSetInput {
              "A Domain, Subdomain or DomainAlias. An alias subdomain is not supported."
              id: ID!
              enabled: Boolean!
              "Omitted or null leaves the current HTTP-redirect setting unchanged."
              httpForward: Boolean
            }

            extend type Mutation {
              letsEncryptSet(input: LetsEncryptSetInput!): VirtualHost!
            }
        ';
    }

    public function getResolvers(ExtensionContext $context): array
    {
        $read = static function ($source, array $args, $ctx) use ($context) {
            $context->requireScope($ctx, Scope::DOMAINS_READ);
            $vhost = $context->virtualHost($source);

            if ($vhost->getKind() === 'alssub') {
                // No column represents an alias subdomain; there is never a row.
                return null;
            }

            return $context->loader()->keyed(
                'SGW_LetsEncrypt:row',
                $vhost->getKind() . ':' . $vhost->getKey(),
                static function (array $keys) use ($context) {
                    $columns = array('dmn' => 'domain_id', 'als' => 'alias_id', 'sub' => 'subdomain_id');
                    $where = array();
                    $bind = array();

                    foreach ($keys as $key) {
                        list($kind, $id) = explode(':', $key, 2);
                        $where[] = $columns[$kind] . ' = ?';
                        $bind[] = (int)$id;
                    }

                    $found = array();

                    foreach ($context->db()->rows(
                        'SELECT domain_id, alias_id, subdomain_id, cert_name, http_forward, status, state
                         FROM letsencrypt WHERE ' . implode(' OR ', $where),
                        $bind
                    ) as $row) {
                        if ($row['alias_id'] !== null) {
                            $key = 'als:' . $row['alias_id'];
                        } elseif ($row['subdomain_id'] !== null) {
                            $key = 'sub:' . $row['subdomain_id'];
                        } else {
                            $key = 'dmn:' . $row['domain_id'];
                        }

                        $provisioning = Provisioning::fromStatus($row['status']);
                        $found[$key] = array(
                            'enabled'      => letsencrypt_isEnabled($row['status']),
                            'httpForward'  => (bool)$row['http_forward'],
                            'certName'     => $row['cert_name'],
                            'provisioning' => array(
                                'state'   => $provisioning->getState(),
                                'raw'     => $row['status'],
                                'settled' => $provisioning->isSettled(),
                                // The table keeps the certbot failure text in its own
                                // 'state' column rather than in 'status' itself (which
                                // just holds the literal 'error'), so it is substituted
                                // in here rather than trusting Provisioning's own guess.
                                'message' => $row['status'] === 'error' ? $row['state'] : null
                            )
                        );
                    }

                    return $found;
                }
            );
        };

        return array(
            'Domain.letsEncrypt'      => $read,
            'Subdomain.letsEncrypt'   => $read,
            'DomainAlias.letsEncrypt' => $read,

            'Mutation.letsEncryptSet' => static function ($source, array $args, $ctx) use ($context) {
                $input = (array)$args['input'];

                // Spec section 8.1, in order: ownership (NOT_FOUND), scope
                // (FORBIDDEN), feature (FEATURE_UNAVAILABLE), settled (CONFLICT).
                $vhost = $context->targetVirtualHost(
                    $context->identity($ctx), $input['id'] ?? null, Scope::DOMAINS_WRITE, 'input.id'
                );

                Guard::requireFeature($vhost->getKind() !== 'alssub', 'letsEncrypt');
                Guard::requireFeature(
                    SGW_LetsEncrypt::customerHasLetsEncrypt($vhost->getOwnerId()), 'letsEncrypt'
                );
                Guard::requireState((string)$vhost->getStatus(), array(Provisioning::STATE_OK));

                $row = letsencrypt_getOrCreateRow($vhost->getKind(), $vhost->getKey(), $vhost->getOwnerId());

                if ($row === false) {
                    // targetVirtualHost() already proved the vhost itself exists and
                    // is reachable, so this would mean the two disagree - not
                    // something a caller's input can provoke.
                    throw new \RuntimeException('The virtual host resolved but its Let\'s Encrypt row did not.');
                }

                // The row's own status: a request the backend has not caught up
                // with yet must not be overwritten (spec section 8.3).
                Guard::requireState(
                    (string)$row['status'],
                    array(Provisioning::STATE_OK, Provisioning::STATE_DISABLED, Provisioning::STATE_ERROR)
                );

                $httpForward = array_key_exists('httpForward', $input) && $input['httpForward'] !== null
                    ? (bool)$input['httpForward']
                    : (bool)$row['http_forward'];

                letsencrypt_applyChange((int)$row['letsencrypt_id'], (bool)$input['enabled'], $httpForward);

                // Wake the daemon. Never inside a transaction.
                $context->core()->sendRequest();

                // The object returned must be read after the write (decision D18).
                $context->loader()->reset();

                return $context->virtualHostReference($vhost);
            }
        );
    }

    public function getComplexity(): array
    {
        // No list fields, so nothing to charge beyond the default.
        return array();
    }
}
