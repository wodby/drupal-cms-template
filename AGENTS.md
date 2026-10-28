# Agent guidance for this Drupal site

This codebase is a Composer-managed Drupal site.

## Detect the command runner first

Do not assume DDEV is installed. Before running anything, work out how this codebase invokes Composer
and Drush, from the project root:

1. **DDEV (preferred)** — a `.ddev/` directory exists *and* `ddev` is on `PATH` (`command -v ddev`).
   Use `ddev composer` and `ddev drush`, as described below.
2. **Local PHP + Composer** — no usable `ddev`, but `composer` is on `PATH` (`command -v composer`).
   Run `composer install` if `vendor/` doesn't exist yet. Use plain `composer`, and check
   whether `vendor/bin/drush` exists (some packages of this project ship without Drush), if it does, use that (not a global `drush`); if it doesn't, skip the Drush workflow below.

State which one you picked before running commands. If neither applies, stop and report it rather
than guessing at a command that will fail. In the workflow sections below, substitute the Composer
and Drush commands for the option you resolved.

## Local environment (DDEV)

Run commands from the project root:

- Start or restart the local environment with `ddev start`, `ddev restart`, and `ddev stop`.
- Install PHP dependencies with `ddev composer install`.
- Open the site with `ddev launch`.
- Run Drush commands with `ddev drush <command>` such as `status`, `user:login`,  `cache:rebuild`, and `updatedb`.

DDEV project config lives in `.ddev/config.yaml`. Use `.ddev/config.local.yaml` for machine-specific overrides.

## Common Drupal workflows

- Add a module with `ddev composer require drupal/<project>`, then  `ddev drush pm:enable --yes <module_machine_name>`, then `ddev drush cache:rebuild`.
- Apply database updates after code changes with `ddev drush updatedb --yes`.
- Import repository configuration into the site with `ddev drush config:import --yes`.
- Export site configuration back to the repo with `ddev drush config:export --yes`.

## Guardrails

- Do not commit secrets or machine-local overrides such as `.env`, `settings.local.php`, or `.ddev/config.local.yaml`.
- Do not commit `vendor/` or uploaded files under `web/sites/*/files`.
- Do not edit Drupal core or contributed projects in place.
- Put custom code in `web/modules/custom` and `web/themes/custom`.

## References

- https://docs.ddev.com/en/stable/
- https://www.drupal.org/docs/administering-a-drupal-site/configuration-management/workflow-using-drush
