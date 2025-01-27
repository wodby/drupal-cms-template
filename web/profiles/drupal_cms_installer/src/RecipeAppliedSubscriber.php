<?php

declare(strict_types=1);

namespace Drupal\drupal_cms_installer;

use Drupal\Core\Recipe\RecipeAppliedEvent;
use Drupal\Core\State\StateInterface;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Tracks our applied recipes.
 *
 * This is done to increase fault tolerance. On hosting plans that don't have
 * a ton of RAM or computing power to spare, the possibility of the installer
 * timing out or failing in mid-stream is increased, especially with a big,
 * complex distribution like Drupal CMS. Tracking the recipes which have been
 * applied allows the installer to recover and "pick up where it left off",
 * without applying recipes that have already been applied successfully. Once
 * the install is done, the list of recipes is deleted.
 *
 * @see drupal_cms_installer_apply_recipes()
 * @see drupal_cms_installer_uninstall_myself()
 */
final class RecipeAppliedSubscriber implements EventSubscriberInterface {

  /**
   * The state key that stores the record of our applied recipes.
   *
   * @var string
   */
  public const STATE_KEY = 'drupal_cms_installer.applied_recipes';

  public function __construct(
    private readonly StateInterface $state,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    return [
      RecipeAppliedEvent::class => 'onApply',
    ];
  }

  /**
   * Reacts when a recipe is applied to the site.
   *
   * @param \Drupal\Core\Recipe\RecipeAppliedEvent $event
   *   The event object.
   */
  public function onApply(RecipeAppliedEvent $event): void {
    $list = $this->state->get(static::STATE_KEY, []);
    $list[] = basename($event->recipe->path);
    $this->state->set(static::STATE_KEY, $list);
  }

}
