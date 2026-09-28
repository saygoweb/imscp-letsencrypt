<?php
/**
 * Ownership scoping for letsencrypt_getOrCreateRow(): a customer must never
 * be able to reach another customer's domain, alias or subdomain by simply
 * changing the id in the URL. See frontend/client/letsencrypt_edit.php's
 * _client_getEditData(), the one caller on the client side.
 *
 * Plain PHP printing TAP, alongside common.t:
 *
 *   prove --exec php test/frontend
 *
 * exec_query() is faked with a tiny in-memory table, good enough to prove
 * the query is scoped to the owner passed in, without booting the real
 * panel or a MySQL connection. The double insists on exactly as many bound
 * values as '?' placeholders, so it fails loudly - as a real driver would -
 * if a future edit removes the "AND domain_admin_id = ?" filter while still
 * passing the owner id as a bound value.
 */

// One row per (kind, key), as if seeded by a real install: key 1 is owned by
// admin 1, key 2 by admin 2. Neither fixture defines key 99, standing in for
// an id that does not exist at all.
$fixture = array(
    'dmn' => array(
        1 => array('domain_admin_id' => 1, 'domain_name' => 'one.example', 'letsencrypt_id' => 501, 'cert_name' => 'one.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''),
        2 => array('domain_admin_id' => 2, 'domain_name' => 'two.example', 'letsencrypt_id' => 502, 'cert_name' => 'two.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''),
    ),
    'als' => array(
        1 => array('domain_admin_id' => 1, 'alias_name' => 'one-alias.example', 'letsencrypt_id' => 511, 'cert_name' => 'one-alias.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''),
        2 => array('domain_admin_id' => 2, 'alias_name' => 'two-alias.example', 'letsencrypt_id' => 512, 'cert_name' => 'two-alias.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''),
    ),
    'sub' => array(
        1 => array('domain_admin_id' => 1, 'domain_name' => 'one.example', 'subdomain_name' => 'sub', 'letsencrypt_id' => 521, 'cert_name' => 'sub.one.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''),
        2 => array('domain_admin_id' => 2, 'domain_name' => 'two.example', 'subdomain_name' => 'sub', 'letsencrypt_id' => 522, 'cert_name' => 'sub.two.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''),
    ),
);

class FakeStatement
{
    private $row;
    public function __construct($row) { $this->row = $row; }
    public function rowCount() { return $this->row === null ? 0 : 1; }
    public function fetchRow($style = null) { return $this->row; }
}

/**
 * Recognise which of letsencrypt_getOrCreateRow()'s three queries ran from a
 * fragment of its WHERE clause that survives whatever the rest of the SQL
 * looks like, then apply the same owner filter a real
 * "AND domain_admin_id = ?" would.
 */
function exec_query($sql, $bind = array())
{
    global $fixture;

    if (strpos($sql, 'domain.domain_id = ?') !== false) {
        $kind = 'dmn';
        $idCol = 'domain_id';
    } elseif (strpos($sql, 'domain_aliasses.alias_id = ?') !== false) {
        $kind = 'als';
        $idCol = 'alias_id';
    } elseif (strpos($sql, 'subdomain.subdomain_id = ?') !== false) {
        $kind = 'sub';
        $idCol = 'subdomain_id';
    } else {
        throw new \Exception("test double does not recognise this query: $sql");
    }

    $placeholders = substr_count($sql, '?');
    if ($placeholders !== count($bind)) {
        throw new \Exception(
            "$kind query: $placeholders placeholder(s) in the SQL but " . count($bind) . ' bound value(s)'
        );
    }

    $key = $bind[0];
    $ownerId = isset($bind[1]) ? $bind[1] : null;

    $row = null;
    if (isset($fixture[$kind][$key])) {
        $candidate = $fixture[$kind][$key];
        // Only one placeholder at all means the query is not scoped by owner -
        // the bug this test guards against - so every id is let through.
        if ($placeholders < 2 || $candidate['domain_admin_id'] == $ownerId) {
            $row = array($idCol => $key) + $candidate;
        }
    }

    return new FakeStatement($row);
}

require __DIR__ . '/../../frontend/client/letsencrypt_common.php';

use function SGW_LetsEncrypt\letsencrypt_getOrCreateRow;

$n = 0;
$failed = 0;

function is($got, $expected, $name)
{
    global $n, $failed;
    $n++;
    if ($got === $expected) {
        echo "ok $n - $name\n";
        return;
    }
    $failed++;
    echo "not ok $n - $name\n";
    echo '#          got: ' . var_export($got, true) . "\n";
    echo '#     expected: ' . var_export($expected, true) . "\n";
}

foreach (array('dmn' => 'domain', 'als' => 'alias', 'sub' => 'subdomain') as $kind => $label) {
    $owned = letsencrypt_getOrCreateRow($kind, 1, 1);
    is($owned === false, false, "the owner reaches their own $label");
    is($owned['letsencrypt_id'], $fixture[$kind][1]['letsencrypt_id'], "and sees its real row");

    $stolen = letsencrypt_getOrCreateRow($kind, 2, 1);
    is($stolen, false, "another customer's $label id is refused, not merely someone else's data");

    $missing = letsencrypt_getOrCreateRow($kind, 99, 1);
    is($missing, false, "an id that names no $label at all is refused the same way");

    is($stolen, $missing, ($kind === 'als' ? 'an' : 'a') . " $label that exists but is not owned looks exactly like one that does not exist");

    // The rightful owner of key 2 is unaffected by customer 1's attempt on it.
    $other = letsencrypt_getOrCreateRow($kind, 2, 2);
    is($other === false, false, "the other customer still reaches their own $label");
}

echo "1..$n\n";
exit($failed ? 1 : 0);
