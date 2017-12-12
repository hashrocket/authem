### 3.0.0 ###

* Remove support for Rails < v4.2
* Fix sign out issue when user is not signed in

### 2.2.0 ###
* Support multi channel authentication - see [README](README.md)

### 2.1.0 ###

* Rails 5 compatibility

### 2.0.2 ###

* Signing up resets CSRF token [[PR](https://github.com/paulelliott/authem/pull/27)]

### 2.0.1 ###

* Add JRuby support

### 2.0.0 ###

* Complete rewrite from scratch
* Store sessions in the database
* Multiple sessions and models support
* Drop Sorcery support
* Initializer is no longer needed

### 1.4.0 ###

* Use SecureRandom for token generation
* Lots of support file cleanup
* Some code cleanup
* All of this is thanks to Pavel Pravosud (@rwz). This guy is fantastic.

### 1.3.3 ###

* Regenerate session token when user signs out (Issue #21)

### 1.3.2 ###

* Prevent duplicate password validations on Authem::User

### 1.3.1 ###

* Bump bcrypt dependency for Rails 4.0.1 compatibility

### 1.3.0 ###

* Check for presence of password in authenticate
* Reconstantize user class when requested
* Add remember token to generated migrations
* Remove weird commas from generated migrations

### 1.2.0 ###

* Use `sign_in?` helper in `require_user` (Issue #13)
* Update rails dependencies to final release versions

### 1.1.1 ###

* Lock down bcrypt version per Rails' requirements
