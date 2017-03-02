[![Gem Version](https://badge.fury.io/rb/kitchen-habitat.svg)](http://badge.fury.io/rb/kitchen-habitat)

# kitchen-habitat
A Test Kitchen Provisioner for [Habitat](https://habitat.sh)

## Requirements


## Installation & Setup
You'll need the test-kitchen & kitchen-habitat gems installed in your system, along with kitchen-vagrant or some ther suitable driver for test-kitchen. 

## Configuration Settings

### Depot settings

* `depot_url`
  * Target Habitat Depot to use to install packages.
  * Defaults to `nil` (which will use the default depot settings for the `hab` CLI).

### Supervisor Settings

* `hab_sup`
  * Package identification for the supervisor to use.
  * Defaults to `core/hab-sup`
* `hab_sup_listen_http`
  * Port for the supervisor's sidecar to listen on.
  * Defaults to `nil`
* `hab_sup_listen_gossip`
  * Port for the supervisor's gossip communication
  * Defaults to `nil`

### Package Settings

* `artifact_name`
  * Artifact package filename to install and run.
  * Used to upload and test a local artifact.
  * Example - `core-jq-static-1.5-20170127185151-x86_64-linux.hart`
  * Defaults to `nil`
* `package_origin`
  * Origin for the package to run.
  * Defaults to `core`, or or, if `artifact_name` is supplied, the `package_origin` will be parsed from the filename of the hart file.
* `package_name`
  * Package name for the supervisor to run.
  * Defaults to the suite name or, if `artifact_name` is supplied, the `package_name` will be parsed from the filename of the hart file.
* `package_version`
  * Package version of the package to be run.
  * Defaults to `nil` or if `artifact_name` is supplied, the `package_version` will be parsed from the filename of the hart file.
* `package_timestamp`
  * Package timestamp of the package to be run.
  * Defaults to `nil` or if `artifact_name` is supplied, the `package_timestamp` will be parsed from the filename of the hart file.


## Example 

```yaml
provisioner:
  - name: habitat
    hab_sup: core/hab/0.16.0
    

suite:
  - name: core/redis
```