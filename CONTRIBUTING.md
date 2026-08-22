# Contributing to kitchen-habitat

Thanks for your interest in improving kitchen-habitat. Bug reports, feature requests, and pull requests are all welcome.

## Reporting issues

Report bugs and request features on the [issue tracker](https://github.com/test-kitchen/kitchen-habitat/issues). For bugs, please include:

- the version of kitchen-habitat and Test Kitchen you are using
- the Habitat version, and whether the supervisor came from a depot or a local `.hart`
- your `kitchen.yml`
- the output of the failing command, ideally with `-l debug`

Converges that fail while waiting for a service to come up are often a
`service_load_timeout` that is too short rather than a bug — worth ruling out
first.

## Development setup

Clone the repository and install the dependencies:

```sh
git clone https://github.com/test-kitchen/kitchen-habitat.git
cd kitchen-habitat
bundle install
```

## Running the tests

Run the unit tests and the style check together:

```sh
bundle exec rake
```

Run them individually:

```sh
bundle exec rake test    # RSpec unit tests
bundle exec rake style   # Cookstyle / RuboCop
```

To run a single spec file:

```sh
bundle exec rspec spec/kitchen/provisioner/habitat_spec.rb
```

Many style offenses can be corrected automatically:

```sh
bundle exec cookstyle -a
```

The unit tests assert on the shell and PowerShell the provisioner generates.
They do not install Habitat or start a supervisor, so they run anywhere.

## Manual testing

Because the unit tests only check the generated commands, anything touching
installation, service load, or supervisor options should also be run end to end
against a real instance.

Worth exercising separately, since they take different paths through the
provisioner:

- **a depot package**, using `package_origin` and `package_name`
- **a local artifact**, using `artifact_name` or `install_latest_artifact` with a
  `results_directory` produced by a Habitat studio build
- **Linux and Windows**, which have entirely separate command generation
- **multi-service suites**, using `hab_sup_peer` and `hab_sup_bind`

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change, adding or updating tests to cover it.
4. Make sure `bundle exec rake` passes.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the documentation in `README.md` when you add or change a
configuration option.

## Release process

Releases are handled by the maintainers.

1. Update `lib/kitchen-habitat/version.rb` with the new version.
2. Update `CHANGELOG.md`.
3. Merge to `main`; the publish workflow builds the gem and pushes it to
   RubyGems.
