fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios auth

```sh
[bundle exec] fastlane ios auth
```

Check the API key (read-only): signs in and looks up the app record

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

One time, Apple ID: create the App Store Connect record (the API does not allow it)

### ios privacy

```sh
[bundle exec] fastlane ios privacy
```

One time, Apple ID: answer App Privacy as 'Data not collected'

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload texts, category, age rating and screenshots. Nothing is submitted.

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Pick the uploaded build from VERSION.md and submit the version for App Review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
