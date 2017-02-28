[![Gem Version](https://badge.fury.io/rb/kitchen-habitat.svg)](http://badge.fury.io/rb/kitchen-habitat)

# kitchen-habitat
A Test Kitchen Provisioner for [Habitat](https://habitat.sh)

## Requirements


## Installation & Setup
You'll need the test-kitchen & kitchen-habitat gems installed in your system, along with kitchen-vagrant or some ther suitable driver for test-kitchen. 

## Configuration Settings
* depot_url
  * Target Habitat Depot to use to install packages.
  * Defaults to `nil` (which will use the default depot settings for the `hab` CLI).
* hab_sup
  * Package identification for the supervisor to use
  * Defaults to `core/hab-sup`
* package_name
  * Package identification for the supervisor to run.
  * Defaults to the suite name

## Example 

```yaml
provisioner:
  - name: habitat
    hab_sup: core/hab/0.16.0
    

suite:
  - name: core/redis
```