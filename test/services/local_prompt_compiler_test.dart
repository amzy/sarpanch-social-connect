import 'package:flutter_test/flutter_test.dart';
import 'package:sarpanch_social_connect/services/local_prompt_compiler.dart';

void main() {
  const compiler = LocalPromptCompiler();

  test('normalizes whitespace without changing factual text', () {
    expect(
      compiler.compile('  Road   repair  completed  \r\n\r\n  Ward 4  '),
      'Road repair completed\n\nWard 4',
    );
  });

  test('removes only exact duplicate lines', () {
    expect(
      compiler.compile('Ward 4\nRoad repaired\nWard 4\nward 4'),
      'Ward 4\nRoad repaired\nward 4',
    );
  });

  test('preserves Hindi names, numbers and dates', () {
    const source = 'श्री रामलाल जी\nदिनांक: 12-11-2026\n250 परिवार';
    expect(compiler.compile(source), source);
  });

  test('rejects input beyond the Worker limit', () {
    expect(
      () => compiler.compile('a' * 5001),
      throwsA(isA<FormatException>()),
    );
  });

  test('empty input stays empty', () {
    expect(compiler.compile(' \n  \n'), '');
  });
}
