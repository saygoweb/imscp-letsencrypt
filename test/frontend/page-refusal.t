<?php
/**
 * Every client page refuses a customer the feature gate turns away.
 *
 * SGW_LetsEncrypt::customerHasLetsEncrypt() used to hard-code "return true;",
 * so a customer failing the gate could never actually reach these pages -
 * there was nothing for a test like this one to catch. Now that the gate is
 * real, each of letsencrypt.php, letsencrypt_edit.php and
 * letsencrypt_status.php must refuse with the panel's usual not-allowed
 * handling (showBadRequestErrorPage()) before doing anything customer-facing,
 * the same way imscp-apache-cache's client pages handle
 * customerHasApacheCache() being false.
 *
 * Each page is required for real, in the order it appears below, so its own
 * "Main" section runs the gate check for real; showBadRequestErrorPage() is
 * faked to throw rather than exit, so this test can tell the page actually
 * stopped there rather than pressing on. The three pages declare no
 * colliding function names, so all three can be required once each, in this
 * one process.
 *
 * Plain PHP printing TAP, alongside common.t, ownership.t, customer-gate.t
 * and edit-log-domain-name.t:
 *
 *   prove --exec php test/frontend
 */

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
        // The gate itself is customer-gate.t's job; here it is simply wired
        // to always refuse, so this test is only about each page's own
        // reaction to that.
        public static function customerHasLetsEncrypt($customerId)
        {
            return false;
        }
    }
}

namespace {
    /**
     * Thrown by the showBadRequestErrorPage() stub in place of the real
     * "print an error page and exit", so a page that reaches it can be told
     * apart, from the outside, from one that pressed on regardless.
     */
    class RefusedSignal extends \Exception
    {
    }

    function check_login($role)
    {
    }

    function is_xhr()
    {
        // letsencrypt_status.php's own XHR-only guard, ahead of the feature
        // gate in that file - true, so a refusal in this test can only be
        // the feature gate's doing.
        return true;
    }

    function showBadRequestErrorPage()
    {
        throw new RefusedSignal();
    }

    $_SESSION['user_id'] = 1;

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

    function refused($file)
    {
        try {
            require $file;
        } catch (RefusedSignal $e) {
            return true;
        }
        return false;
    }

    is(
        refused(__DIR__ . '/../../frontend/client/letsencrypt.php'),
        true,
        'letsencrypt.php refuses a customer without the feature'
    );
    is(
        refused(__DIR__ . '/../../frontend/client/letsencrypt_edit.php'),
        true,
        'letsencrypt_edit.php refuses a customer without the feature'
    );
    is(
        refused(__DIR__ . '/../../frontend/client/letsencrypt_status.php'),
        true,
        'letsencrypt_status.php refuses a customer without the feature'
    );

    echo "1..$n\n";
    exit($failed ? 1 : 0);
}
