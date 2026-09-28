# i-MSCP LetsEncrypt Plugin

Plugin that provides domains with LetsEncrypt SSL certificates.

See [Changelog](CHANGELOG.md) for a detailed description of what has changed in each version.

>Disclaimer: This plugin is not likely to be that well supported.  It works for me, for what I need, right now. YMMV.  If you want a full featured supported plugin I would suggest the [LetsEncrypt Plugin](https://i-mscp.net/filebase/index.php/File/33-LetsEncrypt/) from the iMSCP developers.

Testing and bug reports are welcome.

## Requirements

* i-MSCP 1.5.3-maintenance (plugin version v2.x)
* i-MSCP 1.5.x (plugin version v1.5.x)
* i-MSCP 1.4.x (plugin version v1.5.x)
* i-MSCP 1.3.x (up to version v1.1.1)

Plugin version 2.0.x has been tested with i-MSCP version 1.5.3-maintenance on Debian Buster 10.10

Plugin version 1.4.x has been tested with i-MSCP version 1.4.7 on Debian Stretch 9.4

Plugin version 1.5.x has been tested with i-MSCP version 1.5.x on Debian Stretch 9.4

Note that the plugin managemnet in i-MSCP 1.5.3-maintenance may be broken awaiting a merge of the following pull-requests to fix the issues:
* [Fix PluginManager](https://github.com/i-MSCP/imscp/pull/108)
* [Add _ to plugin name validation](https://github.com/i-MSCP/imscp/pull/109)

The plugin has been tested with the 1.5.3-maintenance-sgw branch [available here](https://github.com/saygoweb/imscp).

## Installation

Download the SGW_LetsEncrypt.tgz release file from the releases page.  Don't download the Git source archive if
you plan to upload using the plugin management interface. 

1. Upload the plugin through the plugin management interface
2. Install the plugin through the plugin management interface

## Building

Packaging is driven by [phpmake](https://github.com/saygoweb/phpmake), which reads the targets from
`makefile.json`.

```
make.phar package
```

| target        | effect                                                            |
|---------------|-------------------------------------------------------------------|
| `package`     | build the release archive, currently `package-tar`                |
| `package-tar` | package the plugin as `SGW_LetsEncrypt.tgz`                       |
| `package-zip` | package the plugin as `SGW_LetsEncrypt.zip`                       |
| `db-backup`   | dump the development database to `data/imscp_dev.sql.gz`          |

Only tgz and bzip2 archives can be uploaded through the i-MSCP plugin management interface, which is
why `package` builds the tgz. `package-zip` is kept for the odd occasion a zip is wanted.

`db-backup` connects as `$USER` and takes the password from the `password_db` environment variable.

What is kept out of the release archive is listed in `upload-exclude.txt` for tar and
`upload-exclude-zip.txt` for zip.

## GraphQL

When the [SGW_GraphQL](https://github.com/saygoweb/imscp-graphql) plugin is also installed, this
plugin adds a `letsEncrypt` field to `Domain`, `Subdomain` and `DomainAlias`, and a
`letsEncryptSet` mutation, through SGW_GraphQL's extension hook (see its
`docs/EXTENSIONS.md`). Nothing changes when SGW_GraphQL is not installed: the plugin loads no
GraphQL class unless that plugin is installed and dispatches `onGraphQLRegisterExtensions`.

There is no column for an alias subdomain (`alssub`) in this plugin's own `letsencrypt` table, so
`letsEncrypt` reads as `null` on one, and `letsEncryptSet` refuses one with `FEATURE_UNAVAILABLE`.

```graphql
query {
  node(id: "RG9tYWluOjE") {
    ... on Domain {
      name
      letsEncrypt {
        enabled
        httpForward
        certName
        provisioning { state settled message }
      }
    }
  }
}

mutation {
  letsEncryptSet(input: { id: "RG9tYWluOjE", enabled: true, httpForward: true }) {
    name
    ... on Domain { letsEncrypt { enabled provisioning { state } } }
  }
}
```

`letsEncrypt` is `null` until a certificate has been requested at least once. `enabled` reflects
the last settled request - it is `false` while `provisioning.state` is `PENDING`, exactly as the
client edit page shows the checkbox on a fresh visit. `provisioning.message` carries the certbot
failure reason when `provisioning.state` is `ERROR`. `letsEncryptSet` refuses the request with
`CONFLICT` when either the virtual host or this plugin's own row is still pending a previous
change.

Its tests live in `test/graphql/`, run with the SGW_GraphQL plugin's own PHPUnit rather than with
`test/run.sh` - see [Testing](#testing).

## Testing

The tests run against a real i-MSCP installation: the docker stack in the sibling
[i-MSCP checkout](https://github.com/saygoweb/imscp) (`docker/imscp up`, see its
`docker/README.md`), or the CI image built from it.

```
test/docker.sh               # from this machine, inside the sibling docker stack
sudo test/run.sh             # on an i-MSCP host, or in CI
make.phar test               # same as test/docker.sh
```

Either takes test files to run just those, e.g. `test/docker.sh test/backend/40-run.t`.
`test/run.sh` is the single entry point: it exits non-zero when any test fails, and its
header lists the environment it reads.

| file                                | covers                                                              |
|-------------------------------------|---------------------------------------------------------------------|
| `test/backend/00-compile.t`         | every Perl and PHP source file parses                               |
| `test/backend/10-unit.t`            | error reporting and domain type helpers                             |
| `test/backend/20-httpd-conf.t`      | the vhost rewrite, against the installed `domain.tpl`               |
| `test/backend/30-selfsigned-cert.t` | the placeholder `ssl_certs` row, and putting it back on failure     |
| `test/backend/40-run.t`             | `run()` end to end for domains, aliases and subdomains              |
| `test/backend/90-dns-lookup.t`      | the DNS pre-check; only with `SGW_NETWORK_TESTS=1`                  |
| `test/backend/95-install.t`         | installing certbot; only with `SGW_DESTRUCTIVE_TESTS=1`             |
| `test/frontend/common.t`            | the status helpers the client pages use                             |

The tests are safe to run on a shared development server. They do not need the
plugin to be installed. Everything they write to the database goes into
`TEMPORARY` tables that shadow `letsencrypt`, `ssl_certs`, `domain`,
`domain_aliasses` and `subdomain` for the test's own connection. certbot is replaced
by `backend/certbot-auto-test.pm`, and the files it and the tests create are removed
when each test ends.

### GraphQL tests

`test/graphql/` is run separately, with the [SGW_GraphQL](https://github.com/saygoweb/imscp-graphql)
plugin's own PHPUnit rather than `test/run.sh`, since it needs that plugin's Composer
dependencies and its `IntegrationTestCase`/`AuthzTestCase` bootstrap of the real panel and
database:

```
php7.4 /var/www/imscp-plugins/imscp-graphql/vendor/bin/phpunit -c test/graphql/phpunit.xml --do-not-cache-result
```

run from this plugin's own checkout, on a box where both plugins sit side by side under
`/var/www/imscp-plugins` - the shared development stack, or the CI image, where the
`graphql-test` workflow job clones a shallow copy of SGW_GraphQL if it is not already there.
Also safe on a shared server: it seeds and rolls back its own fixture, the same way SGW_GraphQL's
own tests do, and only creates the `letsencrypt` table itself (via this plugin's own `sql/`
migrations) when it is missing.

## How to Help

* Report issues you find in our [GitHub Issue Tracker](https://github.com/saygoweb/imscp-letsencrypt/issues). Please report with as much detail as you can. Simply saying "It doesn't work" will gain you sympathy, but not a lot else.
* Want to contribute code? Go right ahead, fork the project on GitHub, pull requests are welcome.

## License

```
i-MSCP  SGW_LetsEncrypt plugin
Copyright (C) 2017 Cambell Prince <cambell.prince@gmail.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 of the License

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
```

See [LICENSE](LICENSE)

## Authors

* Cambell Prince <cambell.prince@gmail.com>
