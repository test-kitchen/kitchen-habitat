[![Gem Version](https://badge.fury.io/rb/kitchen-habitat.svg)](http://badge.fury.io/rb/kitchen-habitat)

# kitchen-habitat
A Test Kitchen Provisioner for [Habitat](https://habitat.sh)

## Requirements


## Installation & Setup
You'll need the test-kitchen & kitchen-habitat gems installed in your system, along with kitchen-vagrant or some other suitable driver for test-kitchen.

## Configuration Settings

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
  * Defaults to `nil
* `hab_sup_listen_http`
  * Port for the supervisor's sidecar to listen on.
  * Defaults to `nil`
* `hab_sup_listen_gossip`
  * Port for the supervisor's gossip communication
  * Defaults to `nil`
* `hab_sup_group`
  * Service group for the supervisor to belong do.
  * Default is `default`
* `hab_sup_bind`
  * Service group for the supervisor to bind to.
  * Default is `[]`
* `hab_sup_peer`
  * IP and port (e.g. `192.168.1.86:9010`) of the supervisor of which to connect to join the ring.
  * Default is `[]`

### Package Settings

* `artifact_name`
  * Artifact package filename to install and run.
  * Used to upload and test a local artifact.
  * Package should be located in the `results_directory`
  * Example - `core-jq-static-1.5-20170127185151-x86_64-linux.hart`
  * Defaults to `nil`
* `results_directory`
  * Directory (relative to the location of the .kitchen.yml) containing package artifacts (harts) to copy to the remote system
  * Defaults to checking the local directory for a `results` directory, then its parent (`../results`) and grandparent (`../../results`), which should accomodate most studio layouts.
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
