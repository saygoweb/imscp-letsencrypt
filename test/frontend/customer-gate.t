<?php
/**
 * SGW_LetsEncrypt::customerHasLetsEncrypt(): the customer-facing feature gate.
 *
 * True only when both hold: the panel's SSL feature is switched on
 * (ENABLE_SSL, the same setting customerHasFeature('ssl') tests in
 * gui/include/Client.php) and the customer's own account is active
 * (admin_status = 'ok'). Before this fix the function hard-coded
 * "return true;" and its memo was a single static value shared by every
 * customer, rather than one per customer.
 *
 * This requires the real SGW_LetsEncrypt.php, with the panel surface it
 * touches (Registry::get('config'), exec_query()) faked - a real MySQL
 * connection is not available to a plain "php test/file.t" run. Its parent
 * class, AbstractPlugin, is stubbed empty: nothing this test calls reaches
 * it, but the class must exist for "class SGW_LetsEncrypt extends
 * AbstractPlugin" to parse.
 *
 * Plain PHP printing TAP, alongside common.t and ownership.t:
 *
 *   prove --exec php test/frontend
 */

namespace iMSCP\Plugin {
    class AbstractPlugin
    {
    }
}

namespace iMSCP {
    class Registry
    {
        public static $config = array();

        public static function get($name)
        {
            return $name === 'config' ? self::$config : null;
        }
    }
}

namespace {
    class FakeStatement
    {
        private $row;
        public function __construct($row) { $this->row = $row; }
        public function fetchRow($style = null) { return $this->row; }
    }

    // admin_id => admin_status, as the 'admin' table would have it.
    $GLOBALS['_admins'] = array(1 => 'ok', 2 => 'ok', 3 => 'suspended');
    $GLOBALS['_queryCount'] = 0;

    function exec_query($sql, $bind = array())
    {
        $GLOBALS['_queryCount']++;

        if (stripos($sql, 'FROM admin') === false) {
            throw new \Exception("test double does not recognise this query: $sql");
        }

        list($customerId, $wantStatus) = $bind;
        $status = isset($GLOBALS['_admins'][$customerId]) ? $GLOBALS['_admins'][$customerId] : null;

        return new FakeStatement(array('cnt' => $status === $wantStatus ? 1 : 0));
    }

    require __DIR__ . '/../../SGW_LetsEncrypt.php';

    $gate = '\iMSCP\Plugin\SGW_LetsEncrypt\SGW_LetsEncrypt::customerHasLetsEncrypt';

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

    \iMSCP\Registry::$config = array('ENABLE_SSL' => 1);
    is($gate(1), true, 'ENABLE_SSL on and an active account: has the feature');
    is($gate(3), false, 'ENABLE_SSL on but a suspended account: refused');
    is($gate(99), false, 'ENABLE_SSL on but no such admin at all: refused, not an error');

    // The bug this guards against: one static value shared by every customer
    // rather than a memo per customer. Read back in the opposite order from
    // how they were first computed above, so a single shared value could not
    // accidentally read correct by coincidence.
    is($gate(3), false, 'the suspended account is still refused after the active one was allowed');
    is($gate(1), true, 'and the active account is still allowed after the suspended one was refused');

    $queriesSoFar = $GLOBALS['_queryCount'];
    $gate(1);
    is($GLOBALS['_queryCount'], $queriesSoFar, 'a repeat check for the same customer does not hit the database again');

    \iMSCP\Registry::$config = array('ENABLE_SSL' => 0);
    is($gate(2), false, 'ENABLE_SSL off: refused even for an active account');

    // A customer already memoised under ENABLE_SSL=1 above must not be
    // recomputed differently just because ENABLE_SSL changed under it -
    // the memo is for the life of the request, exactly as long as the
    // config is expected to stay put.
    is($gate(1), true, 'a customer already memoised keeps their answer for the rest of the request');

    echo "1..$n\n";
    exit($failed ? 1 : 0);
}
