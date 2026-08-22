# kitchen-habitat

[![Gem Version](https://badge.fury.io/rb/kitchen-habitat.svg)](https://badge.fury.io/rb/kitchen-habitat)
[![Unit](https://github.com/test-kitchen/kitchen-habitat/actions/workflows/unit.yml/badge.svg)](https://github.com/test-kitchen/kitchen-habitat/actions/workflows/unit.yml)
[![linters](https://github.com/test-kitchen/kitchen-habitat/actions/workflows/linters.yml/badge.svg)](https://github.com/test-kitchen/kitchen-habitat/actions/workflows/linters.yml)

A [Test Kitchen](https://kitchen.ci/) provisioner for [Habitat](https://habitat.sh). It installs the Habitat
supervisor on your test instance, loads the service you are working on, and waits for it to come up, so you can test
Habitat packages the same way you would test a cookbook.

> This documentation uses [Cinc Workstation](https://cinc.sh/) and the `cinc` commands throughout. Everything here
> works identically with Chef Workstation — see [Using with Chef](#using-with-chef).

## Requirements

- Ruby 3.1 or later (already satisfied if you use Cinc Workstation)
- A Test Kitchen driver to supply instances, such as
  [kitchen-vagrant](https://github.com/test-kitchen/kitchen-vagrant),
  [kitchen-docker](https://github.com/test-kitchen/kitchen-docker), or
  [kitchen-ec2](https://github.com/test-kitchen/kitchen-ec2)
- A Habitat package to test, either from a depot or built locally in a Habitat studio

The provisioner installs the `hab` binary on the instance itself, so you do not need Habitat installed locally unless
you are building artifacts to upload.

## Installation

This provisioner ships as part of [Cinc Workstation](https://cinc.sh/start/workstation/). If you have Cinc
Workstation installed, there is nothing else to install.

To install it into a standalone Ruby:

```sh
gem install kitchen-habitat
```

Or with Bundler, add it to your `Gemfile` alongside Test Kitchen and a driver:

```ruby
gem "test-kitchen"
gem "kitchen-habitat"
gem "kitchen-vagrant"
```

...then run `bundle install`.

## Quick Start

Run a package straight from the depot:

```yaml
---
driver:
  name: vagrant

provisioner:
  name: habitat
  hab_license: accept
  package_origin: core
  package_name: redis

platforms:
  - name: ubuntu-22.04

suites:
  - name: default
```

Then:

```sh
cinc kitchen converge
```

Or run the whole cycle:

```sh
cinc kitchen test
```

`hab_license: accept` is required before Habitat will run — see
[the Chef license documentation](https://docs.chef.io/chef_license_accept.html#habitat).

## Configuration Settings

All options below are set under the `provisioner:` key in `kitchen.yml`, or per suite under
`suites[].provisioner:`.

### General

* `hab_license`
  * Habitat license acceptance. Set to `accept` to run at all.
  * See the [Chef license documentation](https://docs.chef.io/chef_license_accept.html#habitat).
  * Defaults to `nil`
* `hab_version`
  * Version of the `hab` CLI to install on the instance.
  * Defaults to `latest`
* `hab_channel`
  * Release channel the `hab` CLI itself is installed from.
  * Defaults to `stable`
* `root_path`
  * Directory on the instance used to stage artifacts and configuration.
  * Defaults to the driver's sandbox path.

### Depot settings

* `depot_url`
  * Target Habitat Depot to use to install packages.
  * Defaults to `nil` (which will use the default depot settings for the `hab` CLI from ~/.hab/etc/cli.toml).

### Supervisor Settings

* `hab_sup_origin`
  * Package identification for the supervisor to use.
  * Defaults to `core`, or, if `hab_sup_artifact_name` is supplied, the `hab_sup_origin` will be parsed from the filename of the hart file.
* `hab_sup_name`
  * Name of the supervisor package
  * Defaults to `hab-sup`, or, if `hab_sup_artifact_name` is supplied, the `hab_sup_name` will be parsed from the filename of the hart file.
* `hab_sup_version`
  * Version number of `hab-sup` to run
  * Defaults to `nil`, or, if `hab_sup_artifact_name` is supplied, the `hab_sup_version` will be parsed from the filename of the hart file.
* `hab_sup_release`
  * Release of the `hab-sup` package to run
  * Defaults to `nil`, or, if `hab_sup_artifact_name` is supplied, the `hab_sup_release` will be parsed from the filename of the hart file.
* `hab_sup_artifact_name`
  * Artifact package name for a custom supervisor to run
  * Used to upload and test a local supervisor.
  * Package should be located in the `results_directory`
  * Defaults to `nil`
* `hab_sup_listen_http`
  * Port for the supervisor's sidecar to listen on.
  * Defaults to `nil`
* `hab_sup_listen_gossip`
  * Port for the supervisor's gossip communication
  * Defaults to `nil`
* `hab_sup_listen_ctl`
  * Listen address for the supervisor's control gateway (`--listen-ctl`).
  * Defaults to `nil`
* `hab_sup_group`
  * Service group for the supervisor to belong to.
  * Defaults to `nil`, which leaves the supervisor in its own `default` group.
* `hab_sup_bind`
  * Service group for the supervisor to bind to.
  * Default is `[]`
* `hab_sup_peer`
  * IP and port (e.g. `192.168.1.86:9010`) of the supervisor of which to connect to join the ring.
  * Default is `[]`
* `hab_sup_ring`
  * Ring key name
  * Default is `nil`

### Package Settings

* `artifact_name`
  * Artifact package filename to install and run.
  * Used to upload and test a local artifact.
  * Package should be located in the `results_directory`
  * Example - `core-jq-static-1.5-20170127185151-x86_64-linux.hart`
  * Defaults to `nil`
* `results_directory`
  * Directory (relative to the location of `kitchen.yml`) containing package artifacts (harts) to copy to the remote system
  * Defaults to checking the local directory for a `results` directory, then its parent (`../results`) and grandparent (`../../results`), which should accommodate most studio layouts.
* `package_origin`
  * Origin for the package to run.
  * Defaults to `core`, or, if `artifact_name` is supplied, the `package_origin` will be parsed from the filename of the hart file.
* `package_name`
  * Package name for the supervisor to run.
  * Defaults to the suite name or, if `artifact_name` is supplied, the `package_name` will be parsed from the filename of the hart file.
* `package_version`
  * Package version of the package to be run.
  * Defaults to `nil` or if `artifact_name` is supplied, the `package_version` will be parsed from the filename of the hart file.
* `package_release`
  * Package release of the package to be run.
  * Defaults to `nil` or if `artifact_name` is supplied, the `package_release` will be parsed from the filename of the hart file.
* `service_topology`
  * The topology for the service to run in.  Valid values are `nil`, `standalone`, `leader`
  * Defaults to `nil` which is `standalone`
* `service_update_strategy`
  * Describes how package updates are to be applied.  Valid values are `nil`, `at-once`, `rolling`.
  * Default is `nil`, which does not check for package updates.
* `channel`
  * Release channel the package under test is installed from and loaded with.
  * Defaults to `stable`
* `service_load_timeout`
  * Seconds to wait for the service to come up after it is loaded, before failing the converge.
  * Raise this for services that are slow to start.
  * Defaults to `300`
* `config_directory`
  * Directory containing a user.toml or/and a default.toml, hooks, and configuration files to be passed to the service under test.
  * Defaults to `nil`
* `override_package_config`
  * Tell the supervisor to load the the configuration files and hooks from `config_directory` instead of what was packaged with the service.  (Uses `--config-from` via the `hab-sup` CLI.)
* `user_toml_name`
  * Name of the file to be used as the user.toml for the service under test.
  * Defaults to `user.toml`
* `install_latest_artifact`
  * Choose to install latest artifact.
  * Must specify `artifact_name` or `package_origin` and `package_name`
  * `package_version` and `package_release` will be ignored
  * Defaults to `false`

### EAS Application Dashboard Settings

* `event_stream_application`
  * The name of your application.
  * Defaults to `nil`
* `event_stream_environment`
  * The application environment for this supervisor.
  * Defaults to `nil`
* `event_stream_site`
  * Describes the physical (for example, datacenter) or cloud-specific (for example, the AWS region) location where your services are deployed.
  * Defaults to `nil`
* `event_stream_url`
  * The Chef Automate URL with port 4222 specified.
  * Defaults to `nil`
* `event_stream_token`
  * Chef Automate Token
  * Defaults to `nil`

> NOTE: All 5 EAS settings are required for it to report to Automate.

## Examples

Run the core-redis package

```yaml
driver:
  name: vagrant

provisioner:
  name: habitat
  hab_sup_origin: core
  hab_sup_name: sup
  package_origin: core
  package_name: redis

platforms:
  - name: ubuntu-16.04

suites:
  - name: default
```

Two node: elasticsearch and kibana

```yaml
driver:
  name: docker

provisioner:
  name: habitat
  hab_sup_origin: core
  hab_sup_name: sup

platforms:
  - name: ubuntu-16.04

suites:
  - name: elasticsearch
    provisioner:
      package_origin: core
      package_name: elasticsearch
    driver:
      instance_name: elastic

  - name: kibana
    provisioner:
      package_origin: core
      package_name: kibana
      hab_sup_peer:
        - elastic
      hab_sup_bind:
        - elasticsearch:elasticsearch.default
    driver:
      instance_name: kibana
      links: elastic:elastic
```

EAS Application Dashboard Example

``` yaml
---
driver:
  name: azurerm

driver_config:
  subscription_id: <%= ENV['subscription_id'] %>
  location: <%= ENV['region'] %>
  machine_size: "Standard_DS2_v2"

verifier:
  name: inspec

provisioner:
  name: habitat
  hab_version: 'latest'
  hab_license: accept
  event_stream_application: Effortless
  event_stream_environment: stable
  event_stream_site: <%= ENV['region'] %>
  event_stream_url: automate.example.com:4222
  event_stream_token: <%= ENV['automate_token'] %>

platforms:
  - name: windows
    driver:
      image_urn: MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest
      vm_name: windows
    provisioner:
      package_origin: <%= ENV['package_origin'] %>
      package_name: <%= ENV['package_name'] %>

suites:
  - name: default
    verifier:
      inspec_tests:
        - tests
```

Latest Artifact example

> This example assumes you've already done a build via hab studio.

```yaml
driver:
  name: vagrant
  customize:
    memory: 2048

verifier:
  name: inspec

provisioner:
  name: habitat
  hab_version: 'latest'
  hab_license: accept

platforms:
  - name: wildfly-local
    driver:
      box: bento/ubuntu-16.04
    provisioner:
      package_origin: jmassardo
      package_name: wildfly
      results_directory: results
      install_latest_artifact: true

suites:
  - name: default
    verifier:
      inspec_tests:
        - tests
```

Apply `user.toml` Example

> This example assumes that you have a `/configs/user.toml` in your project directory.

```yaml
driver:
  name: vagrant
  customize:
    memory: 2048

verifier:
  name: inspec

provisioner:
  name: habitat
  hab_version: 'latest'
  hab_license: accept

platforms:
  - name: wildfly
    driver:
      box: bento/ubuntu-16.04
    provisioner:
      package_origin: jmassardo
      package_name: wildfly
      channel: unstable
      config_directory: configs

suites:
  - name: default
    verifier:
      inspec_tests:
        - tests
```

## Using with Chef

This provisioner is not tied to Cinc, and it does not install Cinc or Chef on the instance — it installs the Habitat
supervisor and runs your package. The commands above use Cinc Workstation; with
[Chef Workstation](https://www.chef.io/downloads/tools/workstation) run `kitchen` instead of `cinc kitchen`. No
provisioner configuration changes are needed.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/test-kitchen/kitchen-habitat). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup, how to run the tests, and the release process.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
