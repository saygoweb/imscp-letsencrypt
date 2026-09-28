<?php
/**
 * client_editLetsEncrypt() must log the domain it just changed.
 *
 * It used to build the audit log line from $data['domain_name_utf8'], a key
 * letsencrypt_getOrCreateRow() never sets - the log line silently lost the
 * domain name (and PHP raised an undefined-index notice for it). It should
 * use the vhost's real name, decoded to UTF-8 with decode_idna() the way the
 * rest of the panel logs a domain name.
 *
 * This drives frontend/client/letsencrypt_edit.php exactly the way a real
 * POST does - $_SESSION, $_GET and $_POST are set up before the file is
 * required, so the require runs the page's own "Main" section, through
 * client_editLetsEncrypt() and write_log(), for real. Everything the Main
 * section touches after that (redirectTo(), which would otherwise send a
 * Location header and exit) is faked, just enough to stop the script
 * without reaching the template rendering this test has no need of.
 *
 * Plain PHP printing TAP, alongside common.t and ownership.t:
 *
 *   prove --exec php test/frontend
 */

// --- Panel surface the page's "Main" section touches before and around
// client_editLetsEncrypt(). Kept to the minimum this path actually reaches.

namespace iMSCP\Event {
    class Events
    {
        const onClientScriptStart = 'onClientScriptStart';
        const onClientScriptEnd = 'onClientScriptEnd';
    }

    class EventAggregator
    {
        private static $instance;
        public static function getInstance()
        {
            return self::$instance ?: (self::$instance = new self());
        }
        public function dispatch($event, $params = array())
        {
        }
    }
}

namespace iMSCP\Plugin\SGW_LetsEncrypt {
    class SGW_LetsEncrypt
    {
        // The customer-gate is fixed by a later PR; here the customer is
        // simply allowed through, so this test is only about the log line.
        public static function customerHasLetsEncrypt($customerId)
        {
            return true;
        }
    }
}

namespace {
    /**
     * Thrown by the redirectTo() stub in place of the real header()+exit(),
     * so requiring the page can be stopped, from the outside, right after
     * client_editLetsEncrypt() returns - without ever reaching the template
     * engine this test does not stub.
     */
    class RedirectSignal extends \Exception
    {
    }

    $GLOBALS['_writeLogCalls'] = array();

    function check_login($role)
    {
    }

    function tr($string)
    {
        return $string;
    }

    function write_log($message, $level)
    {
        $GLOBALS['_writeLogCalls'][] = $message;
    }

    function send_request()
    {
    }

    function set_page_message($message, $type)
    {
    }

    function redirectTo($url)
    {
        throw new RedirectSignal($url);
    }

    function showBadRequestErrorPage()
    {
        throw new \Exception('showBadRequestErrorPage() was not expected to be reached in this test');
    }

    /**
     * i-MSCP's real decode_idna() turns a punycode label back into UTF-8.
     * Standing in for it here so the test can tell the log line apart from
     * one built off the raw (still-punycode) cert_name: only a caller that
     * actually calls decode_idna() sees the mapped name below.
     */
    function decode_idna($domain)
    {
        return $domain === 'xn--mnchen-3ya.example' ? 'münchen.example' : $domain;
    }

    // One existing, owned domain row, as letsencrypt_getOrCreateRow() would
    // find it - its cert_name is still punycode, the way the domain table
    // stores it.
    $fixture = array(
        'dmn' => array(
            1 => array(
                'domain_admin_id' => 1, 'domain_name' => 'xn--mnchen-3ya.example', 'letsencrypt_id' => 501,
                'cert_name' => 'xn--mnchen-3ya.example', 'http_forward' => 0, 'status' => 'ok', 'state' => ''
            )
        )
    );

    class FakeStatement
    {
        private $row;
        public function __construct($row) { $this->row = $row; }
        public function rowCount() { return $this->row === null ? 0 : 1; }
        public function fetchRow($style = null) { return $this->row; }
    }

    function exec_query($sql, $bind = array())
    {
        global $fixture;

        // letsencrypt_applyChange()'s UPDATE: nothing to look up, and no
        // return value the caller reads.
        if (stripos($sql, 'UPDATE letsencrypt') !== false) {
            return new FakeStatement(null);
        }

        if (strpos($sql, 'domain.domain_id = ?') === false) {
            throw new \Exception("test double does not recognise this query: $sql");
        }

        list($key, $ownerId) = array($bind[0], $bind[1]);
        $row = null;
        if (isset($fixture['dmn'][$key]) && $fixture['dmn'][$key]['domain_admin_id'] == $ownerId) {
            $row = array('domain_id' => $key) + $fixture['dmn'][$key];
        }

        return new FakeStatement($row);
    }

    $_SESSION['user_id'] = 1;
    $_SESSION['user_logged'] = 'alice@example.com';
    $_GET['type'] = 'domain';
    $_GET['id'] = 1;
    $_POST['enabled'] = 'yes';
    $_POST['http_forward'] = 'no';

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

    function like($got, $pattern, $name)
    {
        global $n, $failed;
        $n++;
        if (preg_match($pattern, $got)) {
            echo "ok $n - $name\n";
            return;
        }
        $failed++;
        echo "not ok $n - $name\n";
        echo '#     got: ' . var_export($got, true) . "\n";
        echo '#     does not match: ' . $pattern . "\n";
    }

    $redirected = false;
    try {
        require __DIR__ . '/../../frontend/client/letsencrypt_edit.php';
    } catch (RedirectSignal $e) {
        $redirected = true;
    }

    is($redirected, true, 'the edit still redirects to letsencrypt.php on success');
    is(count($GLOBALS['_writeLogCalls']), 1, 'exactly one line was logged');

    $logged = $GLOBALS['_writeLogCalls'][0];
    like($logged, '/münchen\.example/', 'the log line names the domain, decoded to UTF-8');
    is(strpos($logged, 'domain_name_utf8'), false, 'no leftover reference to the old, unset key');

    echo "1..$n\n";
    exit($failed ? 1 : 0);
}
