# Task Completion

Pre-commit and deployment validation checklist.

## Syntax & Compilation Checks
Always lint files before committing or packaging to catch syntax errors:
* **PHP:**
  ```bash
  php -l SGW_LetsEncrypt.php
  find frontend/ -name "*.php" -exec php -l {} \;
  ```
* **Perl:**
  ```bash
  perl -c backend/SGW_LetsEncrypt.pm
  ```

## Run Local Tests
Run backend test suites inside the Vagrant VM:
```bash
prove -r test/backend/
```

## Packaging Verification
Ensure a clean distribution package can be compiled:
```bash
make.phar package
```
*Verify that `SGW_LetsEncrypt.tgz` is successfully built without any warnings or missing file warnings.*
