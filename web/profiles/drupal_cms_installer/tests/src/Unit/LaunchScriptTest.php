<?php

declare(strict_types=1);

namespace Drupal\Tests\drupal_cms_installer\Unit;

use Drupal\Component\FileSystem\FileSystem;
use Drupal\Tests\UnitTestCase;
use Symfony\Component\Process\Process;

/**
 * @group drupal_cms_installer
 */
final class LaunchScriptTest extends UnitTestCase {

  public function testProjectNameAlreadyExists(): void {
    if (PHP_OS_FAMILY === 'Windows') {
      $this->markTestSkipped('This test does not work on Windows, because it needs to call Unix commands.');
    }

    $working_dir = dirname(__FILE__, 7);
    $project_name = basename($working_dir);

    $php = PHP_BINARY;
    $php_code = <<<END
#!/usr/bin/env $php
<?php
if (\$argv[1] === "list") {
  echo "Yes, there is a $project_name project";
}
else {
  echo implode(" ", array_slice(\$argv, 1)) . "\n";
}
END;
    $mock_ddev = FileSystem::getOsTemporaryDirectory() . '/ddev';
    file_put_contents($mock_ddev, $php_code);
    $this->assertTrue(chmod($mock_ddev, 0755) && is_executable($mock_ddev));

    $launcher = new Process([$working_dir . '/launch-drupal-cms.sh']);
    $launcher->setEnv([
      'PATH' => dirname($mock_ddev) . ':' . getenv('PATH'),
    ]);
    $launcher->setWorkingDirectory($working_dir);
    $launcher->run();
    unlink($mock_ddev);

    $this->assertSame(0, $launcher->getExitCode(), $launcher->getErrorOutput());
    $output = explode("\n", $launcher->getOutput());
    $this->assertStringStartsWith('config ', $output[0]);
    $this->assertStringContainsString("--project-name=$project_name-2", $output[0]);
  }

}
