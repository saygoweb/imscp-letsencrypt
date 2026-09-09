# Conventions

Architectural conventions, naming patterns, and design details for the codebase.

## Localization & UI
* **Translations:** All user-facing strings must be localized using language files inside `l10n/` (e.g. `en_GB.php`). Do not hardcode strings in templates.
* **MVC Separation:** UI logic (controllers) resides in `frontend/` while presentation resides in `themes/default/view/`.

## Event Listeners and Hooks
* **Frontend events:** Handled in `SGW_LetsEncrypt.php`'s `register()` method via i-MSCP event managers.
* **Backend events:** `backend/SGW_LetsEncrypt.pm` registers to i-MSCP engine events like `afterHttpdBuildConf` to alter web server configurations and inject Let's Encrypt certificates.

## Database State Model
* The plugin tracks cert states inside the `letsencrypt` table.
* The `state` field is text-typed to store detailed failing logs/responses from Certbot, making error debugging transparent to users.
