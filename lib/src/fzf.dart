import 'dart:convert' as convert;
import 'dart:io' as io;

Future<T> _fzf<T>(Iterable<String> input, bool isMulti) async {
  input = input.toList()..sort();
  final process = await io.Process.start(
    'fzf',
    <String>[
      '--tac',
      if (isMulti) '--multi',
    ],
  );
  List<String> selectedFields = <String>[];
  final stdoutSub = process.stdout
      .transform(const convert.Utf8Decoder())
      .transform(const convert.LineSplitter())
      .listen((String line) {
    if (line.isEmpty) {
      return;
    }
    selectedFields.add(line);
  });
  // Forward fzf UI
  final stderrSub = process.stderr.listen(
    (List<int> bytes) => io.stderr.add(bytes),
  );

  // feed input to FZF
  process.stdin.add(<String>[...input, ''].join('\n').codeUnits);

  await Future.wait<void>(<Future<void>>[
    stdoutSub.asFuture<void>(),
    stderrSub.asFuture<void>(),
    process.exitCode,
  ]);
  if (selectedFields.isEmpty) {
    // this probably means user quit fzf with ESC
    throw StateError('Never received any STDOUT from fzf');
  }
  if (isMulti) {
    return selectedFields as T;
  }

  return selectedFields.single as T;
}

Future<String> fzfSingle(Iterable<String> input) => _fzf<String>(input, false);
Future<List<String>> fzfMulti(Iterable<String> input) => _fzf<List<String>>(input, true);
