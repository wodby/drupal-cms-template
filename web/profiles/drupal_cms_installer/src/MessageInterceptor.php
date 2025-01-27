<?php

declare(strict_types=1);

namespace Drupal\drupal_cms_installer;

use Drupal\Core\Messenger\MessengerInterface;
use Drupal\Core\StringTranslation\TranslatableMarkup;

/**
 * Decorates the messenger to suppress or alter certain install-time messages.
 */
final class MessageInterceptor implements MessengerInterface {

  private array $reject = [
    'Congratulations, you installed @drupal!',
  ];

  public function __construct(
    private readonly MessengerInterface $decorated,
  ) {
    if (getenv('IS_DDEV_PROJECT')) {
      $this->reject[] = 'All necessary changes to %dir and %file have been made, so you should remove write permissions to them now in order to avoid security risks. If you are unsure how to do so, consult the <a href=":handbook_url">online handbook</a>.';
    }
  }

  /**
   * {@inheritdoc}
   */
  public function addMessage($message, $type = self::TYPE_STATUS, $repeat = FALSE): static {
    $raw = $message instanceof TranslatableMarkup
      ? $message->getUntranslatedString()
      : strval($message);

    if (!in_array($raw, $this->reject, TRUE)) {
      $this->decorated->addMessage($message, $type, $repeat);
    }
    return $this;
  }

  /**
   * {@inheritdoc}
   */
  public function addStatus($message, $repeat = FALSE): static {
    return $this->addMessage($message, self::TYPE_STATUS, $repeat);
  }

  /**
   * {@inheritdoc}
   */
  public function addError($message, $repeat = FALSE): static {
    return $this->addMessage($message, self::TYPE_ERROR, $repeat);
  }

  /**
   * {@inheritdoc}
   */
  public function addWarning($message, $repeat = FALSE): static {
    return $this->addMessage($message, self::TYPE_WARNING, $repeat);
  }

  /**
   * {@inheritdoc}
   */
  public function all(): array {
    return $this->decorated->all();
  }

  /**
   * {@inheritdoc}
   */
  public function messagesByType($type): array {
    return $this->decorated->messagesByType($type);
  }

  /**
   * {@inheritdoc}
   */
  public function deleteAll(): array {
    return $this->decorated->deleteAll();
  }

  /**
   * {@inheritdoc}
   */
  public function deleteByType($type): array {
    return $this->decorated->deleteByType($type);
  }

}
