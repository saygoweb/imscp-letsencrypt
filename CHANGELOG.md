# iMSCP LetsEncrypt Plugin - Changelog

## Version 2.2.0

* Answer the http-01 challenge from a webroot instead of through certbot's Apache plugin. The Apache
  plugin parsed the whole Apache configuration for each certificate and reloaded Apache three times
  per certificate: on a server with hundreds of vhosts that was about three minutes of CPU per
  certificate, enough to overload the server during a renewal run. Certificates are now requested
  with `certbot certonly --webroot -w /var/www/sgw-letsencrypt` and no installer.
* The plugin installs `sgw_letsencrypt.conf` in Apache's `conf-available/` and enables it. It serves
  `/.well-known/acme-challenge/` from the webroot on every vhost. i-MSCP's redirect and proxy
  forwards already leave that path out, so forwarded domains are served too. The webroot is outside
  every document root, so customer `.htaccess` rules do not apply to it.
* Existing certificates are migrated on update. The renewal configs of the plugin's lineages (in
  `renewal/` and, for disabled domains, `renewal-disabled/`) that still use the Apache plugin are
  switched to `authenticator = webroot`, with `webroot_path` and a `[[webroot_map]]` for each name on
  the certificate, and their `installer` line is removed. Each config is first copied as it was to
  `/etc/letsencrypt/renewal-backup/<time>/`. Lineages the plugin does not manage are left alone, and
  running the migration again changes nothing.
* With no installer, certbot no longer reloads Apache after a renewal. Two renewal hooks do it
  instead: `renewal-hooks/deploy/40-sgw-letsencrypt` raises a flag for each renewed certificate,
  and `renewal-hooks/post/50-sgw-letsencrypt` reloads Apache once at the end of the run when the
  flag is up.
* Uninstalling removes the Apache conf, the webroot and the hooks. As before, certificates and
  their renewal configs are kept.
* To roll back, install 2.1.9 again and copy the configs from the backup back into
  `/etc/letsencrypt/` (for example `cp -a /etc/letsencrypt/renewal-backup/<time>/. /etc/letsencrypt/`).

## Version 2.1.9

* Deleting or disabling a domain, alias or subdomain that has a Let's Encrypt certificate deletes or
  disables it (#51). Deleting the certificate used to queue the host for a rebuild, which replaced its
  pending delete or disable: the host's mail and FTP accounts and certificate were removed, but the
  host itself was rebuilt without SSL and left in place.

## Version 2.1.8

* Report a failed certificate request in words the site owner can act on (#46), instead of certbot's
  raw output. The common failures each get their own message saying what is wrong and what to do: the
  name is not in the public DNS, the site cannot be reached on port 80, the check request reached
  something other than this site, a CAA record forbids the certificate, too many requests were made
  recently (with when to try again), or a problem on the server (contact support). Anything else gets a
  general message. The messages do not name certbot or the certificate authority, since apps reading
  them through GraphQL (`provisioning.message`) show them as they are. certbot's own output is logged
  with the message for support.
* The DNS check from 2.1.7 words its messages the same way.

## Version 2.1.7

* Check that a domain points at this server before asking Let's Encrypt for its certificate (#45).
  A name that resolves to any other address is reported against the domain, saying where it points,
  instead of failing Let's Encrypt's validation and using up one of the few failed validations it
  allows an hour. A `www.` name that points elsewhere is left off the certificate. The server's
  addresses are its i-MSCP IPs, `BASE_SERVER_PUBLIC_IP` and those of its network interfaces; set
  `check_dns_points_here` to `false` in `config.php` for sites reached through a proxy or CDN.
* Use the certificate certbot already holds when it is for exactly the names wanted and is not due
  for renewal (#47). certbot is not run and the domain is not looked up, so a network or Let's
  Encrypt outage no longer fails a domain whose certificate is good. A certificate within 30 days
  of expiry, or for different names, still goes through certbot.

## Version 2.1.6

* Remove the LetsEncrypt entry from the reseller panel (#20). The plugin has no reseller features,
  and the page behind the menu was never adapted to this plugin: it queried columns the
  `letsencrypt` table does not have and loaded its template from the wrong path, so opening it
  failed with an error.

## Version 2.1.5

* Fix re-enabling a disabled customer (#42): disabling deleted the domain's renewal config and
  orphaned its `live/` and `archive/` directories, so on re-enable certbot 5.9 issued a new
  certificate, failed to save it with "archive directory exists", and the domain was rebuilt
  without an SSL vhost. Disabling now moves the renewal config to
  `/etc/letsencrypt/renewal-disabled/`, and it is put back when the domain is enabled again or its
  certificate is requested; certbot then keeps the existing certificate.
* Fix deleting a certificate (#40): only the renewal config was removed, so requesting the same name
  later failed or created an unused `<name>-0001` lineage while the site went on serving the old,
  never-renewed certificate. Deleting now runs `certbot delete` and removes whatever `live/`,
  `archive/` and renewal config it leaves.
* certbot is now always given `--cert-name`, so a certificate lands in the lineage the vhost uses. If
  certbot still saves it as `<name>-NNNN`, the request is reported as failed, naming the duplicate.
  The `www` name is only left off when it does not exist; when the lookup is inconclusive it is kept
  if the certificate in use has it, rather than reissuing the certificate without it.
* Lineages already orphaned by earlier versions (no renewal config, or one certbot cannot load) are
  handed back to certbot: when `live/<name>` links into `archive/<name>` as certbot lays it out, a
  renewal config is written for it, with the account and server of another lineage, and certbot keeps
  or renews the certificate in place. The site keeps its certificate throughout, which matters because
  `certbot --apache` refuses to run while a vhost names a missing file. A lineage that cannot be
  adopted is moved to `/etc/letsencrypt/orphaned/<name>-<time>/` before a new certificate is
  requested, and put back if the request fails. Existing `<name>-NNNN` duplicates are left alone and
  can be removed with `certbot delete --cert-name <name>-NNNN`.
* A certificate request for a domain that is still disabled now fails with a message saying so,
  instead of restoring its renewals and rebuilding (re-enabling) the domain.
* Deleting a certificate removes its files only after the domain has been queued for its rebuild
  without SSL; if queueing fails, the files are kept and the delete is reported as failed.

## Version 2.1.3

* Implement the customer-facing feature gate: `SGW_LetsEncrypt::customerHasLetsEncrypt()` used
  to hard-code `return true;` (everyone had the feature). It now requires both that the panel's
  SSL feature is switched on (`ENABLE_SSL`, the same setting `customerHasFeature('ssl')` tests)
  and that the customer's own account is active (`admin_status = 'ok'`). Its per-request memo
  was also a single value shared by every customer rather than one per customer; fixed alongside.
* Re-enable the client navigation link, gated on the same check, which had been unconditionally
  shown since 2017.
* The client pages (`letsencrypt.php`, `letsencrypt_edit.php`, `letsencrypt_status.php`) already
  refused a customer failing the gate; this had never actually been exercised until the gate
  itself became real.
* The GraphQL extension's write path, which already called this gate through
  `Guard::requireFeature()`, now actually enforces it: a customer failing the gate gets
  `FEATURE_UNAVAILABLE`.

## Version 2.1.2

* Fix the audit log line written when a customer edits a domain's LetsEncrypt settings:
  it read `$data['domain_name_utf8']`, a key that was never set, so the log line lost the
  domain name entirely (and PHP raised an undefined-index notice on every edit). It now logs
  the vhost's real name, decoded to UTF-8 with `decode_idna()` the way the rest of the panel
  logs a domain name.

## Version 2.1.1

* Security fix: `letsencrypt_getOrCreateRow()` (used by the client edit page for every domain,
  alias and subdomain lookup) never checked that the vhost it found actually belonged to the
  customer asking for it, so any logged-in customer could view or edit another customer's
  LetsEncrypt setting by changing the `id` in the URL. The lookup is now scoped to the owner id
  the caller already trusts - `$_SESSION['user_id']` on the client pages, `$vhost->getOwnerId()`
  from the GraphQL extension, which was not affected since it already authorised the vhost before
  calling in. An id that belongs to someone else now behaves exactly like an id that does not
  exist.

## Version 2.1.0

* Add GraphQL support, through the SGW_GraphQL plugin's extension hook. See the README's
  GraphQL section. A `letsEncrypt` field on `Domain`, `Subdomain` and `DomainAlias`, and a
  `letsEncryptSet` mutation; only active when SGW_GraphQL is installed, and only ever loaded then.
* The client edit page's read-or-create and write logic is now shared with the GraphQL
  extension, in two new functions in `letsencrypt_common.php`:
  `letsencrypt_getOrCreateRow()` and `letsencrypt_applyChange()`. No change to the page's own
  behaviour.

## Version 2.0.3

* The LetsEncrypt page now updates the status, note and forward columns of a domain by itself while
  the backend is requesting its certificate, which takes tens of seconds. It polls the new
  /client/letsencrypt_status.php endpoint every three seconds for the first minute, then every ten
  seconds, and stops once no domain is waiting on the backend or after five minutes. A page with
  nothing pending on it never polls.

## Version 2.0.2

* Fix a failing certbot request putting the whole plugin into an error state. A domain whose
  certificate request fails, for instance because its DNS has not propagated yet, is now given
  the 'error' status, the reason reported by certbot is recorded as its note, and an error icon
  is shown against it. The customer can retry by re-enabling the domain.
* The placeholder entry written to ssl_certs before a certificate is requested is now taken back
  when the request fails, so a domain is no longer left with SSL support backed by a certificate
  that was never issued.

## Version 1.5.2

* Fix #15 gethostbyname detection can be fooled:
  a. by using the local resolver and b. by the use of wildcard subdomains

## Version 1.5.1

* Continuing with the renaming of LetsEncrypt to SGW_LetsEncrypt.
* Fix #19 Fatal error: Class 'iMSCP_Plugin_LetsEncrypt' not found

## Version 1.5.0

* Introduced new packaging such that the installation via the iMSCP plugin interface now works.

## Version 1.4.0

* Fix #13 Support iMSCP 1.4.x

## Version 1.1.1

* Fix #7 Invalid Certificate error

## Version 1.1.0

* Implement #1 Support for aliases and subdomains

## Version 1.0.2

* Fix #2 Plugin blocked delete domain / customer
* Fix #3 Full chain not delivered by Apache

## Version 1.0.0

* Creates domain certificates
* Creates www.domain certificates also with subject alternative name 
* Can forward http -> https

### Known Limitations

* Doesn't support subdomains of aliases
