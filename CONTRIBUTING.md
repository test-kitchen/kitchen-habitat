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
directly, so they neither build machines nor need the `hab` CLI installed.

### Integration tests

The unit tests assert on the *text* of the commands the provisioner generates.
They cannot tell you whether those commands actually run, so there are Test
Kitchen suites in `kitchen.yml` that converge for real:

| Suite | What it covers |
| --- | --- |
| `default` | Install the CLI, start a supervisor, install `core/redis` from Builder, load it, and wait for it in `hab svc status`. |
| `user-toml` | A `user.toml` staged from `config_directory` under a non-default `user_toml_name`, installed into `/hab/user` by `prepare_command`, plus a non-default supervisor HTTP gateway. |
| `library-package` | `core/jq-static`, which has no `run` hook. `run_command` must install it and then leave it alone rather than waiting out `service_load_timeout`. |

The assertions live in `test/integration/verify.sh` and are selected by
`KITCHEN_SUITE`.

The suites pin `hab_version` to `1.6.1245`. Habitat 2.x moved the `hab` CLI and
the supervisor into the `chef` origin on Builder, which requires a Personal
Access Token, so an unpinned `install.sh` now fails with `401 Unauthorized`
before `hab` reaches the PATH. `1.6.1245` is the last release whose manifest
points at the still-public `core` origin. Unpin it once the provisioner can
pass a `HAB_AUTH_TOKEN` through and CI has one to pass.

These suites use the `exec` driver, which runs every command on the machine
Test Kitchen is already running on. That is what makes them a real test — a
real `hab` CLI, a real systemd unit, a real supervisor — and it also means
**there is no isolation**. They install packages, add a `hab` user and group,
write to `/etc/systemd/system`, and start a service. Run them on a disposable
machine only:

```sh
bundle exec kitchen test default-ubuntu-2404
```

CI runs all three on a fresh Ubuntu runner per suite, so pushing a branch is
the easiest way to exercise them.

### Windows

There is no automated coverage of the Windows path yet — it installs
`core/windows-service` and edits `HabService.dll.config`, which the `exec`
driver cannot do safely on a shared runner. Test it by hand against a Windows
VM when you touch anything in `install_command`, `init_command`, or
`run_command`: the two platform paths share almost no code, and it is easy to
fix one while breaking the other.

## Documentation

If you add, remove, or change a configuration option, update the configuration
reference in `README.md` in the same pull request. An option that is declared
in `default_config` but never read is a bug, not a documentation problem —
wire it up or take it out rather than describing it as working.

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
