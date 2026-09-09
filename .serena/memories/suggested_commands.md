# Suggested Commands

Durable terminal commands for packaging, database tasks, and testing.

## Packaging & Distribution
To package the plugin into a `.tgz` archive suitable for uploading via the i-MSCP plugin management interface:
```bash
make.phar package
```
*Note: This runs phpmake to generate `SGW_LetsEncrypt.tgz` using `upload-exclude.txt` to filter files.*

## Database Backup (Development Environment)
To back up the local database while working inside the Vagrant VM:
```bash
make.phar db-backup
```
*Note: This connects to the database as `$USER` using the `$password_db` environment variable and dumps to `data/imscp_dev.sql.gz`.*

## Running Backend Tests
Execute the Perl backend tests from the plugin directory when mounted/running within the i-MSCP Vagrant environment:
```bash
prove -r test/backend/
# Or specifically run the Tap harness:
perl test/backend/all.t
```
*Note: These tests require `engine/PerlLib` to be available at the correct relative path (`../../../../../engine/PerlLib` from the test suite).*
