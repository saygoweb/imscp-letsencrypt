# Tech Stack

Language, framework, and environmental requirements for the SGW_LetsEncrypt plugin.

## Core Technologies
* **PHP:** Targets PHP 7.x/8.x (compatible with target i-MSCP version). Powers the plugin frontend UI and controllers.
* **Perl 5:** Powers backend module scripts run by the i-MSCP daemon.
* **Database:** MySQL/MariaDB, accessed via the standard i-MSCP SQL/database layer.

## Frameworks & APIs
* **i-MSCP Plugin Framework:** Relies on the plugin manager APIs. API version requirement is specified in `info.php` (currently `1.5.1`).
* **i-MSCP Core Library:** Backend code accesses `engine/PerlLib` (specifically `iMSCP::*` Perl packages) to interact with the i-MSCP system configuration.

## Build and Package Tools
* **phpmake:** Packages the plugin using task configurations in `makefile.json`. Sourced from https://github.com/saygoweb/phpmake. Run via `make.phar package`.

## Testing Tools
* **TAP::Harness / Test::More:** Standard Perl test execution harness used for backend unit and mock-testing.
