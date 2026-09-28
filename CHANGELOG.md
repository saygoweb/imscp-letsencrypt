# iMSCP LetsEncrypt Plugin - Changelog

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
