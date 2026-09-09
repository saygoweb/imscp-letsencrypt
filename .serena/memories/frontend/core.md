# Frontend Architecture

Deep dive into the PHP presentation and controller layers.

## Class: SGW_LetsEncrypt
The main frontend class (`SGW_LetsEncrypt.php` under namespace `iMSCP\Plugin\SGW_LetsEncrypt`) implements standard lifecycle methods:
* `init()`: Sets up autoloader, configurations, and core hooks.
* `register()`: Listens to client and reseller script startups, plus customer/alias deletion events to clear associated certificates.
* `getRoutes()`: Exposes routing tables for URLs mapping onto controllers.

## Front-end Controllers
Controllers are housed under `frontend/`:
* `frontend/client/letsencrypt.php`: Main page logic for client certificate list.
* `frontend/client/letsencrypt_edit.php`: Code to request, renew, or edit certificates.
* `frontend/client/letsencrypt_status.php`: Polling/viewing current generation status.
* `frontend/client/letsencrypt_common.php`: Common validation and state utilities.

## Templates
Presentation views are in `.tpl` format inside `themes/default/view/`:
* `client/letsencrypt.tpl`: Main client panel layout.
* `client/letsencrypt_edit.tpl`: Certificate request and adjustment forms.
