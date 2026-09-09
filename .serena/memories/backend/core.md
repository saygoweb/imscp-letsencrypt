# Backend Architecture

Deep dive into the Perl daemon processing layer.

## Class: SGW_LetsEncrypt.pm
The background processing class implementing system hooks, written in Perl:
* `_init()`: Registers event listeners on the i-MSCP event manager (e.g. `afterHttpdBuildConf`).
* `run()`: Core entry point for processing queued certbot requests.
* `_updateSelfSignedCertificate()`: Generates initial self-signed certificates as placeholders during the asynchronous certbot request phase to prevent webserver start failure.
* `_letsencryptInstall()` / `_letsencryptConfig()`: Handles the calls to `certbot` to generate or renew the certificates.

## Test Mode & Mocks
* To test the plugin offline or in development environments, `testmode` is toggled inside `backend/SGW_LetsEncrypt.pm`.
* When `testmode` is enabled, the plugin invokes the mock executable `backend/certbot-auto-test.pm` instead of the actual `certbot-auto` script.
* This allows testing the success and failure states of the plugin generation loops without making real Let's Encrypt API requests.
