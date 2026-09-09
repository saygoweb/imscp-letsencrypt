# Project Core Index

Top-level entry point for the i-MSCP LetsEncrypt plugin (`SGW_LetsEncrypt`).

## Overview
This plugin provides domains in i-MSCP (internet Multi Server Control Panel) with Let's Encrypt SSL certificates. It features a frontend UI for clients/resellers to manage certificates, and a backend Perl-based daemon service to automate renewal, certificate generation, and virtual host configuration.

## System & Environment Invariants
* **Development Environment:** Must be mounted inside the i-MSCP Vagrant VM (e.g. `debian_trixie` box or similar under `../imscp/Vagrant`) for execution and testing, due to heavy dependencies on the core i-MSCP codebase and `engine/PerlLib`.
* **Database Updates:** Managed dynamically via migrations in `sql/` that i-MSCP executes during plugin install/update.

## Directory Map
* `SGW_LetsEncrypt.php`: Main entry point/event registration for the PHP frontend.
* `backend/`: Perl module and scripts handling the background daemon actions.
* `frontend/`: Client and reseller PHP controller files.
* `themes/`: HTML/template files for the web views.
* `sql/`: Database schema files.
* `l10n/`: Plugin localization files.
* `test/`: Integration and unit tests for the Perl backend.

## Related Memories
* Learn about the languages, build systems, and version requirements: `mem:tech_stack`
* Find key terminal commands for building, packaging, and debugging: `mem:suggested_commands`
* Understand coding style, state machine flows, and hook patterns: `mem:conventions`
* Verify correctness and fulfill finishing tasks with validation steps: `mem:task_completion`
* Deep dive into PHP controllers, routing, and UI rendering: `mem:frontend/core`
* Deep dive into the Perl daemon architecture, events, and mock testing: `mem:backend/core`
