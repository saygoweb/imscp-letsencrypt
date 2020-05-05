# iMSCP LetsEncrypt Plugin - Changelog

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
