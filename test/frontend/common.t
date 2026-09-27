<?php
/**
 * The status helpers the client pages use to draw each domain's row.
 *
 * Plain PHP printing TAP, so that prove runs it beside the backend tests:
 *
 *   prove --exec php test/frontend
 */

require __DIR__ . '/../../frontend/client/letsencrypt_common.php';

use function SGW_LetsEncrypt\letsencrypt_isPending;
use function SGW_LetsEncrypt\letsencrypt_statusIcon;

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

// The statuses the panel writes for the backend to act on
foreach (array('toadd', 'tochange', 'todelete', 'torestore', 'toenable', 'todisable') as $status) {
    is(letsencrypt_isPending($status), true, "$status is waiting on the backend");
    is(letsencrypt_statusIcon($status), 'reload', "$status shows as in progress");
}

// The statuses the backend leaves behind
foreach (array('ok', 'error', 'disabled') as $status) {
    is(letsencrypt_isPending($status), false, "$status is settled");
}
is(letsencrypt_statusIcon('ok'), 'ok', 'ok shows as ok');
is(letsencrypt_statusIcon('disabled'), 'disabled', 'a domain without LetsEncrypt shows as disabled');
is(letsencrypt_statusIcon('error'), 'error', 'a failed request shows as an error');
is(letsencrypt_statusIcon('something new'), 'error', 'a status nobody knows is not passed off as fine');

is(
    \SGW_LetsEncrypt\LETSENCRYPT_TYPES, array('domain', 'alias', 'subdomain'),
    'domains, aliases and subdomains are listed, in that order'
);

echo "1..$n\n";
exit($failed ? 1 : 0);
