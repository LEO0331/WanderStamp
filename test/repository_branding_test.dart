import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installed web app uses the WanderStamp name', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest['name'], 'WanderStamp');
    expect(manifest['short_name'], 'WanderStamp');
    expect(manifest['start_url'], '.');
  });

  test('deployment and public URLs use the renamed repository path', () {
    final workflow = File('.github/workflows/deploy.yml').readAsStringSync();
    expect(workflow, contains('--base-href "/WanderStamp/"'));

    for (final path in [
      'README.md',
      'web/index.html',
      'web/robots.txt',
      'web/sitemap.xml',
    ]) {
      final content = File(path).readAsStringSync();
      expect(content, contains('https://leo0331.github.io/WanderStamp/'));
      expect(content, isNot(contains('/WarmthFromAfar/')), reason: path);
    }
  });
}
