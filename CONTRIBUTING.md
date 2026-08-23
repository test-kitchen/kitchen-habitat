# Contributing to kitchen-habitat

Thanks for your interest in improving kitchen-habitat. Bug reports, docs fixes,
and pull requests are all welcome.

If you want to talk something through before writing code, `#test-kitchen` on
[Chef Community Slack](https://community-slack.chef.io/) is the place.

## Reporting issues

Report bugs and request features on the [issue
tracker](https://github.com/test-kitchen/kitchen-habitat/issues). For bugs,
please include:

- the version of kitchen-habitat and Test Kitchen you are using
- the platform you are converging (Linux or Windows, and which distribution)
- your `kitchen.yml` with any tokens removed
- the output of the failing command, ideally with `-l debug`

Habitat failures often show up on the instance rather than in the Test Kitchen
output. `kitchen login` followed by `hab svc status` and, on Linux,
`journalctl -u hab-sup`, usually says more than the converge log does.

## Development setup

Clone the repository and install the dependencies:

```sh
git clone https://github.com/test-kitchen/kitchen-habitat.git
cd kitchen-habitat
bundle install
```

## Running the tests

Run the unit tests:

```sh
bundle exec rake test
```

And the style check:

```sh
bundle exec rake style
```

`bundle exec rake` runs both, and is what CI runs.

Many style offenses can be corrected automatically:

```sh
bundle exec cookstyle -a
```

The unit tests exercise the provisioner's generated shell and PowerShell
directly and use [fakefs](https://github.com/fakefs/fakefs) for the file
copying, so they neither build machines nor need the `hab` CLI installed.

### Manual testing against a real machine

The unit tests assert on the *text* of the commands the provisioner generates.
They cannot tell you whether those commands actually work, so changes to the
install, supervisor, or service-load logic should also be exercised for real:

```sh
bundle exec kitchen test
```

Test both a Linux and a Windows platform when you touch anything in
`install_command`, `init_command`, or `run_command` — the two paths share
almost no code, and it is easy to fix one while breaking the other.

## Documentation

If you add, remove, or change a configuration option, update the configuration
reference in `README.md` in the same pull request. An option that is accepted
but not read belongs in the "Options that currently have no effect" table
rather than being described as working.

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change, adding or updating tests to cover it.
4. Make sure `bundle exec rake` passes.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster.

## Release process

Releases are handled by the maintainers.

1. Update `lib/kitchen-habitat/version.rb` with the new version.
2. Update `CHANGELOG.md`.
3. Merge to `main`; the [publish workflow](.github/workflows/publish.yml) builds
   the gem and pushes it to RubyGems.
