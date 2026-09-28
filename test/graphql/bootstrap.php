<?php
/**
 * Bootstrap for this plugin's GraphQL extension tests.
 *
 * Run with the SGW_GraphQL plugin's own PHPUnit, from this checkout's root:
 *
 *   php7.4 /var/www/imscp-plugins/imscp-graphql/vendor/bin/phpunit \
 *       -c test/graphql/phpunit.xml --do-not-cache-result
 *
 * Two things, and only these two, are this file's job:
 *
 *   - require the SAME vendor/autoload.php the panel loads when SGW_GraphQL
 *     is enabled. require_once dedupes it there; a second copy of the same
 *     classes, loaded from anywhere else, fatals with
 *     "Cannot redeclare composerRequire...".
 *   - map iMSCP\Plugin\SGW_LetsEncrypt\ onto THIS checkout, prepended ahead
 *     of the panel's own autoloader - which maps that namespace onto
 *     whichever checkout is linked into gui/plugins, not this worktree.
 */

// SGW_GraphQL's own root: Api\Container needs it to find ITS schema/schema.graphql
// (Container::forTesting()'s first argument), separately from the autoloader
// mapping below, which is this plugin's.
define('SGW_GRAPHQL_DIR', '/var/www/imscp-plugins/imscp-graphql');

$autoload = SGW_GRAPHQL_DIR . '/vendor/autoload.php';

if (!is_file($autoload)) {
    fwrite(
        STDERR,
        "test/graphql/bootstrap.php: $autoload is missing.\n"
        . "Install the SGW_GraphQL plugin's Composer dependencies first, e.g.\n"
        . "  php7.4 /var/www/imscp/gui/bin/composer.phar install --no-interaction --no-progress\n"
        . "  (run from that plugin's own checkout)\n"
    );
    exit(1);
}

require_once $autoload;

// The checkout under test, two levels above this file (test/graphql/bootstrap.php).
$pluginRoot = dirname(__DIR__, 2);

spl_autoload_register(
    static function ($class) use ($pluginRoot) {
        $prefix = 'iMSCP\\Plugin\\SGW_LetsEncrypt\\';

        if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
            return;
        }

        $relative = substr($class, strlen($prefix));
        $file = $pluginRoot . '/' . str_replace('\\', '/', $relative) . '.php';

        if (is_file($file)) {
            require $file;
        }
    },
    true,
    // Prepended: ahead of the panel's own autoloader, once imscp-lib.php has
    // registered it, so this checkout wins over whatever is linked into
    // gui/plugins.
    true
);
