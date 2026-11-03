/// Deterministic, on-device prompt preparation.
///
/// This is deliberately not an LLM: it never paraphrases or infers facts.
/// It normalizes whitespace and removes exact duplicate non-empty lines,
/// preserving the user's original wording, names, dates and figures.
class LocalPromptCompiler {
  const LocalPromptCompiler();

  static const int maxInputCharacters = 5000;

  String compile(String input) {
    final normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[\t ]+'), ' ').trim())
        .toList();

    final seen = <String>{};
    final output = <String>[];
    var previousWasBlank = false;

    for (final line in normalized) {
      if (line.isEmpty) {
        if (output.isNotEmpty && !previousWasBlank) output.add('');
        previousWasBlank = true;
        continue;
      }
      previousWasBlank = false;
      // Exact, case-sensitive deduplication only; no semantic rewriting.
      if (seen.add(line)) output.add(line);
    }

    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }
    final result = output.join('\n');
    if (result.length > maxInputCharacters) {
      throw const FormatException(
        'Post details are too long. Please shorten them to 5,000 characters.',
      );
    }
    return result;
  }
}
