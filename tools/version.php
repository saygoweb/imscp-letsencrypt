#!/usr/bin/env php
<?php
/**
 * i-MSCP SGW_ApacheCache plugin
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

/**
 * Sets the version and the release date in info.php.
 *
 * The panel reads both from info.php, and a plugin whose version has not moved
 * is not offered for update, so the two always change together.
 *
 *   php tools/version.php patch     0.2.0 -> 0.2.1
 *   php tools/version.php minor     0.2.0 -> 0.3.0
 *   php tools/version.php major     0.2.0 -> 1.0.0
 *   php tools/version.php 1.2.3     an explicit version
 *
 * Options:
 *   --date=YYYY-MM-DD  stamp this date rather than today
 *   --force            allow a version that is not newer than the current one
 *   -h, --help         this message
 */

const USAGE = <<<TXT
Usage: php tools/version.php [options] major|minor|patch|X.Y.Z
 Options:
  -h, --help          displays this help
  --date=YYYY-MM-DD   stamp this date rather than today
  --force             allow a version that is not newer than the current one

Sets 'version' and 'date' in info.php.
TXT;

exit(main($argv));

/**
 * @param Array<string> $argv
 * @return int Exit code, 0 on success
 */
function main(Array $argv)
{
    $bump = null;
    $date = date('Y-m-d');
    $force = false;

    // $argv[0] is the script itself, so start at 1.
    for ($i = 1; $i < count($argv); $i++) {
        $arg = $argv[$i];
        if ($arg === '-h' || $arg === '--help') {
            echo USAGE, "\n";
            return 0;
        }
        if (strpos($arg, '--date=') === 0) {
            $date = substr($arg, strlen('--date='));
            if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
                return fail("'$date' is not a date of the form YYYY-MM-DD");
            }
            continue;
        }
        if ($arg === '--force') {
            $force = true;
            continue;
        }
        if ($bump !== null) {
            return fail("unexpected argument '$arg'", true);
        }
        $bump = $arg;
    }

    if ($bump === null) {
        return fail('no version given', true);
    }

    $path = dirname(__DIR__) . '/info.php';
    $info = @file_get_contents($path);
    if ($info === false) {
        return fail("cannot read $path");
    }

    // info.php is rewritten as text rather than regenerated from the array it
    // returns, so that its licence header and layout survive the bump.
    if (!preg_match("/('version'\s*=> )'([^']*)'/", $info, $match)) {
        return fail("no 'version' found in $path");
    }
    $current = $match[2];
    if (!preg_match('/^\d+\.\d+\.\d+$/', $current)) {
        return fail("the current version '$current' is not of the form X.Y.Z");
    }

    $version = nextVersion($current, $bump);
    if ($version === null) {
        return fail("'$bump' is neither major, minor, patch nor a version of the form X.Y.Z", true);
    }
    if (!$force && version_compare($version, $current, '<=')) {
        return fail("$version is not newer than the current $current; pass --force to set it anyway");
    }

    $count = 0;
    $info = preg_replace("/('version'\s*=> )'[^']*'/", "\${1}'$version'", $info, 1, $count);
    if ($count !== 1) {
        return fail("could not set the version in $path");
    }
    $info = preg_replace("/('date'\s*=> )'[^']*'/", "\${1}'$date'", $info, 1, $count);
    if ($count !== 1) {
        return fail("no 'date' found in $path");
    }
    if (@file_put_contents($path, $info) === false) {
        return fail("cannot write $path");
    }

    echo "$current -> $version ($date)\n";
    return 0;
}

/**
 * The version $bump asks for, or null if it asks for nothing recognised.
 *
 * @param string $current A version of the form X.Y.Z
 * @param string $bump 'major', 'minor', 'patch', or a version of the form X.Y.Z
 * @return string|null
 */
function nextVersion($current, $bump)
{
    if (preg_match('/^\d+\.\d+\.\d+$/', $bump)) {
        return $bump;
    }
    list($major, $minor, $patch) = array_map('intval', explode('.', $current));
    switch ($bump) {
        case 'major':
            return ($major + 1) . '.0.0';
        case 'minor':
            return "$major." . ($minor + 1) . '.0';
        case 'patch':
            return "$major.$minor." . ($patch + 1);
    }
    return null;
}

/**
 * Reports why nothing was changed.
 *
 * @param string $message
 * @param bool $usage True to spell the usage out, for a command line that was
 *                    not understood rather than one that could not be carried
 *                    out
 * @return int Exit code, always 1
 */
function fail($message, $usage = false)
{
    fwrite(STDERR, "version.php: $message\n");
    fwrite(STDERR, $usage ? USAGE . "\n" : "Try 'php tools/version.php --help'.\n");
    return 1;
}
