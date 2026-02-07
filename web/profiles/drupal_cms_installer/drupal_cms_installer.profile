<?php

/**
 * @internal
 *   Everything in this file is internal to Drupal CMS and may be changed or
 *   removed at any time, without warning. External code should not interact
 *   with this file at all.
 */

declare(strict_types=1);

use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Site\Settings;
use Drupal\RecipeKit\Installer\Form\AlterBase;
use Drupal\RecipeKit\Installer\Form\SiteTemplateForm;
use Drupal\RecipeKit\Installer\Hooks;
use Drupal\RecipeKit\Installer\Messenger;

/**
 * Implements hook_install_tasks().
 */
function drupal_cms_installer_install_tasks(array &$install_state): array {
  $tasks = Hooks::installTasks($install_state);

  if (getenv('IS_DDEV_PROJECT')) {
    Messenger::reject(
      'All necessary changes to %dir and %file have been made, so you should remove write permissions to them now in order to avoid security risks. If you are unsure how to do so, consult the <a href=":handbook_url">online handbook</a>.',
    );
  }
  return $tasks;
}

/**
 * Implements hook_install_tasks_alter().
 */
function drupal_cms_installer_install_tasks_alter(array &$tasks, array $install_state): void {
  Hooks::installTasksAlter($tasks, $install_state);

  // The site template form is shown during the early installer, so we need a
  // decorator class to alter it.
  $tasks[SiteTemplateForm::class]['function'] = SiteTemplateFormAlter::class;

  // The recipe kit doesn't change the title of the batch job that applies all
  // the recipes, so to override it, we use core's custom string overrides.
  // We can't use the passed-in $install_state here, because it isn't passed by
  // reference.
  $langcode = $GLOBALS['install_state']['parameters']['langcode'];
  $settings = Settings::getAll();
  // @see install_profile_modules()
  $settings["locale_custom_strings_$langcode"]['']['Installing @drupal'] = (string) t('Setting up your site');
  new Settings($settings);
}

/**
 * Implements hook_form_alter().
 */
function drupal_cms_installer_form_alter(array &$form, FormStateInterface $form_state, string $form_id): void {
  Hooks::formAlter($form, $form_state, $form_id);
}

/**
 * Implements hook_form_alter() for install_configure_form.
 */
function drupal_cms_installer_form_install_configure_form_alter(array &$form): void {
  // We always install Automatic Updates, so we don't need to expose the update
  // notification settings.
  $form['update_notifications']['#access'] = FALSE;
}

final class SiteTemplateFormAlter extends AlterBase {

  /**
   * {@inheritdoc}
   */
  protected const string DECORATES = SiteTemplateForm::class;

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state): array {
    $form = parent::buildForm($form, $form_state);

    // Hide the site template starter kit. It's a special case because it's
    // technically a site template, but it's a stub that's only meant for
    // developers to install at the command line with Drush.
    $key = 'drupal_cms_site_template_base';
    unset($form['add_ons']['#options'][$key], $form['add_ons'][$key]);
    return $form;
  }

}
