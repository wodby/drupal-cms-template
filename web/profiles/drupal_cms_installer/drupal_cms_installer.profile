<?php

declare(strict_types=1);

use Composer\InstalledVersions;
use Drupal\Core\DependencyInjection\ContainerBuilder;
use Drupal\Core\Render\Element\Password;
use Drupal\Core\Extension\ModuleInstallerInterface;
use Drupal\Core\File\FileUrlGeneratorInterface;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Messenger\MessengerInterface;
use Drupal\Core\Recipe\Recipe;
use Drupal\Core\Recipe\RecipeRunner;
use Drupal\drupal_cms_installer\Form\RecipesForm;
use Drupal\drupal_cms_installer\Form\SiteNameForm;
use Drupal\drupal_cms_installer\MessageInterceptor;
use Drupal\drupal_cms_installer\RecipeAppliedSubscriber;

const SQLITE_DRIVER = 'Drupal\sqlite\Driver\Database\sqlite';

/**
 * Implements hook_install_tasks().
 */
function drupal_cms_installer_install_tasks(): array {
  // Ensure our forms are loadable in all situations, even if the installer is
  // not a Composer-managed package.
  \Drupal::service('class_loader')
    ->addPsr4('Drupal\\drupal_cms_installer\\', __DIR__ . '/src');

  // If the container can be altered, wrap the messenger service to suppress
  // certain messages.
  $container = \Drupal::getContainer();
  if ($container instanceof ContainerBuilder) {
    $container->set('messenger', new MessageInterceptor(
      \Drupal::messenger(),
    ));
  }

  return [
    'drupal_cms_installer_uninstall_myself' => [
      // As a final task, this profile should uninstall itself.
    ],
  ];
}

/**
 * Implements hook_install_tasks_alter().
 */
function drupal_cms_installer_install_tasks_alter(array &$tasks, array $install_state): void {
  $insert_before = function (string $key, array $additions) use (&$tasks): void {
    $key = array_search($key, array_keys($tasks), TRUE);
    if ($key === FALSE) {
      return;
    }
    // This isn't very clean, but it's the only way to positionally splice into
    // an associative (and therefore by definition unordered) array.
    $tasks_before = array_slice($tasks, 0, $key, TRUE);
    $tasks_after = array_slice($tasks, $key, NULL, TRUE);
    $tasks = $tasks_before + $additions + $tasks_after;
  };
  $insert_before('install_settings_form', [
    'drupal_cms_installer_choose_recipes' => [
      'display_name' => t('Choose add-ons'),
      'type' => 'form',
      'run' => array_key_exists('recipes', $install_state['parameters']) ? INSTALL_TASK_SKIP : INSTALL_TASK_RUN_IF_REACHED,
      'function' => RecipesForm::class,
    ],
    'drupal_cms_installer_site_name_form' => [
      'display_name' => t('Name your site'),
      'type' => 'form',
      'run' => array_key_exists('site_name', $install_state['parameters']) ? INSTALL_TASK_SKIP : INSTALL_TASK_RUN_IF_REACHED,
      'function' => SiteNameForm::class,
    ],
  ]);

  $configure_form_task = $tasks['install_configure_form'];
  unset(
    $tasks['install_install_profile'],
    $tasks['install_configure_form'],
  );
  $insert_before('install_profile_modules', [
    'install_install_profile' => [
      'function' => 'drupal_cms_installer_install_myself',
    ],
    'install_configure_form' => $configure_form_task,
  ]);

  // Set English as the default language; it can be changed mid-stream. We can't
  // use the passed-in $install_state because it's not passed by reference.
  $GLOBALS['install_state']['parameters'] += ['langcode' => 'en'];

  // Wrap the install_profile_modules() function, which returns a batch job, and
  // add all the necessary operations to apply the chosen template recipe.
  $tasks['install_profile_modules']['function'] = 'drupal_cms_installer_apply_recipes';
}

/**
 * Installs the User module, and this profile.
 *
 * @param array $install_state
 *   The current installation state.
 */
function drupal_cms_installer_install_myself(array &$install_state): void {
  // We'll need User installed for the next step, which is configuring the site
  // and administrator account.
  \Drupal::service(ModuleInstallerInterface::class)->install([
    'user',
  ]);
  // Officially install this profile so that its behaviors and visual overrides
  // will be in effect for the remainder of the install process. This also
  // ensures that the administrator role is created and assigned to user 1 in
  // the next step.
  install_install_profile($install_state);
}

/**
 * Implements hook_form_alter() for install_settings_form.
 *
 * @see \Drupal\Core\Installer\Form\SiteSettingsForm
 */
function drupal_cms_installer_form_install_settings_form_alter(array &$form): void {
  // Default to SQLite, if available, because it doesn't require any additional
  // configuration.
  if (extension_loaded('pdo_sqlite') && array_key_exists(SQLITE_DRIVER, $form['driver']['#options'])) {
    $form['driver']['#default_value'] = SQLITE_DRIVER;
    $form['driver']['#type'] = 'select';

    // The database file path has a sensible default value, so move it into the
    // advanced options.
    $form['settings'][SQLITE_DRIVER]['advanced_options']['database'] = $form['settings'][SQLITE_DRIVER]['database'];
    unset($form['settings'][SQLITE_DRIVER]['database']);

    $form['help'] = [
      '#prefix' => '<p class="cms-installer__subhead">',
      '#markup' => t("You don't need to change anything here unless you want to use a different database type."),
      '#suffix' => '</p>',
      '#weight' => -50,
    ];
  }
}

/**
 * Implements hook_form_alter() for install_configure_form.
 *
 * @see \Drupal\Core\Installer\Form\SiteConfigureForm
 */
function drupal_cms_installer_form_install_configure_form_alter(array &$form, FormStateInterface $form_state): void {
  global $install_state;

  $form['#title'] = t('Create your account');

  $form['help'] = [
    '#prefix' => '<p class="cms-installer__subhead">',
    '#markup' => t('Creating an account allows you to log in to your site.'),
    '#suffix' => '</p>',
    '#weight' => -40,
  ];

  $form['site_information']['#type'] = 'container';
  // We collected the site name in a previous step.
  $form['site_information']['site_name'] = [
    '#type' => 'hidden',
    '#default_value' => $GLOBALS['install_state']['parameters']['site_name'],
  ];

  // Use a custom submit handler to set the site email.
  unset($form['site_information']['site_mail']);
  $form['#submit'][] = 'drupal_cms_installer_update_site_mail';

  $form['admin_account']['#type'] = 'container';
  // `admin` is a sensible name for user 1.
  $form['admin_account']['account']['name'] = [
    '#type' => 'hidden',
    '#default_value' => 'admin',
  ];
  $form['admin_account']['account']['mail'] = [
    '#prefix' => '<div class="cms-installer__form-group">',
    '#suffix' => '</div>',
    '#type' => 'email',
    '#title' => t('Email'),
    '#required' => TRUE,
    '#default_value' => $install_state['forms']['install_configure_form']['account']['mail'] ?? '',
    '#weight' => 10,
  ];
  $form['admin_account']['account']['pass'] = [
    '#prefix' => '<div class="cms-installer__form-group">',
    '#suffix' => '</div>',
    '#type' => 'password',
    '#title' => t('Password'),
    '#required' => TRUE,
    '#default_value' => $install_state['forms']['install_configure_form']['account']['pass']['pass1'] ?? '',
    '#weight' => 20,
    '#value_callback' => '_drupal_cms_installer_password_value',
  ];

  // Hide the timezone selection. Core automatically uses client-side JavaScript
  // to detect it, but we don't need to expose that to the user. But the
  // JavaScript expects the form elements to look a certain way, so hiding the
  // fields visually is the correct approach here.
  // @see core/misc/timezone.js
  $form['regional_settings']['#attributes']['class'][] = 'visually-hidden';
  // Don't allow the timezone selection to be tab-focused.
  $form['regional_settings']['date_default_timezone']['#attributes']['tabindex'] = -1;

  // We always install Automatic Updates, so we don't need to expose the update
  // notification settings.
  $form['update_notifications']['#access'] = FALSE;

  $form['actions']['submit']['#value'] = t('Finish');
}

/**
 * Custom submit handler to update the site email.
 */
function drupal_cms_installer_update_site_mail(array &$form, FormStateInterface $form_state): void {
  \Drupal::configFactory()
    ->getEditable('system.site')
    ->set('mail', $form_state->getValue(['account', 'mail']))
    ->save();
}

function _drupal_cms_installer_password_value(&$element, $input, FormStateInterface $form_state): mixed {
  // Work around this fact that Drush and `drupal install`, which submit this
  // form programmatically, assume the password is a password_confirm element.
  if (is_array($input) && $form_state->isProgrammed()) {
    $input = $input['pass1'];
  }
  return Password::valueCallback($element, $input, $form_state);
}

/**
 * Runs a batch job that applies the template and add-on recipes.
 *
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @return array
 *   The batch job definition.
 */
function drupal_cms_installer_apply_recipes(array &$install_state): array {
  // If the installer ran before but failed mid-stream, don't reapply any
  // recipes that were successfully applied.
  $recipes_to_apply = array_diff(
    $install_state['parameters']['recipes'],
    \Drupal::state()->get(RecipeAppliedSubscriber::STATE_KEY, []),
  );

  // If we've already applied all the chosen recipes, there's nothing to do.
  // Since we only start applying recipes once `install_profile_modules()` has
  // finished, we can be safely certain that we already did that step.
  if (empty($recipes_to_apply)) {
    return [];
  }

  $batch = install_profile_modules($install_state);
  $batch['title'] = t('Setting up your site');

  $recipe_operations = [];

  foreach ($recipes_to_apply as $name) {
    $recipe = InstalledVersions::getInstallPath('drupal/' . $name);
    $recipe = Recipe::createFromDirectory($recipe);
    $recipe_operations = array_merge($recipe_operations, RecipeRunner::toBatchOperations($recipe));
  }

  // Only do each recipe's batch operations once.
  foreach ($recipe_operations as $operation) {
    if (in_array($operation, $batch['operations'], TRUE)) {
      continue;
    }
    else {
      $batch['operations'][] = $operation;
    }
  }

  return $batch;
}

/**
 * Implements hook_library_info_alter().
 */
function drupal_cms_installer_library_info_alter(array &$libraries, string $extension): void {
  global $install_state;
  // If a library file's path starts with `/`, the library collection system
  // treats it as relative to the base path.
  // @see \Drupal\Core\Asset\LibraryDiscoveryParser::buildByExtension()
  $base_path = '/' . $install_state['profiles']['drupal_cms_installer']->getPath();

  if ($extension === 'claro') {
    $libraries['maintenance-page']['css']['theme']["$base_path/css/gin-variables.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/fonts.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/installer-styles.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/add-ons.css"] = [];
    $libraries['maintenance-page']['dependencies'][] = 'core/once';
  }
  if ($extension === 'core') {
    $libraries['drupal.progress']['js']["$base_path/js/progress.js"] = [];
  }
}

/**
 * Uninstalls this install profile, as a final step.
 *
 * @see drupal_install_system()
 */
function drupal_cms_installer_uninstall_myself(): void {
  \Drupal::service(ModuleInstallerInterface::class)->uninstall([
    'drupal_cms_installer',
  ]);

  // The install is done, so we don't need the list of applied recipes anymore.
  \Drupal::state()->delete(RecipeAppliedSubscriber::STATE_KEY);

  // Clear all previous status messages to avoid clutter.
  \Drupal::messenger()->deleteByType(MessengerInterface::TYPE_STATUS);

  // Invalidate the container in case any stray requests were made during the
  // install process, which would have bootstrapped Drupal and cached the
  // install-time container, which is now stale (during the installer, the
  // container cannot be dumped, which would normally happen during the
  // container rebuild triggered by uninstalling this profile). We do not want
  // to redirect into Drupal with a stale container.
  \Drupal::service('kernel')->invalidateContainer();
}

/**
 * Implements hook_theme_registry_alter().
 */
function drupal_cms_installer_theme_registry_alter(array &$hooks): void {
  global $install_state;
  $installer_path = $install_state['profiles']['drupal_cms_installer']->getPath();

  $hooks['install_page']['path'] = $installer_path . '/templates';
}

/**
 * Preprocess function for all pages in the installer.
 */
function drupal_cms_installer_preprocess_install_page(array &$variables): void {
  // Don't show the task list or the version of Drupal.
  unset($variables['page']['sidebar_first'], $variables['site_version']);

  global $install_state;
  $images_path = $install_state['profiles']['drupal_cms_installer']->getPath() . '/images';
  $images_path = \Drupal::service(FileUrlGeneratorInterface::class)
    ->generateString($images_path);
  $variables['images_path'] = $images_path;
}
