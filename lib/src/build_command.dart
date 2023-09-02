import 'dart:convert' as convert;
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:engine_build_configs/engine_build_configs.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

const fs = LocalFileSystem();
const fieldSeparator = ' - ';

class BuildCommand extends Command<int> {
  final String name = 'build';
  final String description = 'Build engine targets.';

  Future<int> run() async {
    // TODO persist to disk
    if (argResults!.rest.length != 1) {
      throw Exception('Usage: fer build /path/to/engine/src/flutter');
    }
    final engine = fs.directory(argResults!.rest.first);
    final ciBuilderPath =
        engine.childDirectory('ci').childDirectory('builders');
    if (!ciBuilderPath.existsSync()) {
      throw Exception('Expected ${ciBuilderPath.path} to exist');
    }
    final errors = <String>[];
    final configs = BuildConfigLoader(
      errors: errors,
      buildConfigsDir: ciBuilderPath,
    ).configs;
    final fields = <String>[];
    for (final entry in configs.entries) {
      final targetName = entry.key;
      final config = entry.value;
      for (final build in config.builds) {
        for (final target in build.ninja.targets) {
          fields.add(
            '$targetName$fieldSeparator${build.name}$fieldSeparator${target}',
          );
        }
      }
    }

    if (errors.isNotEmpty) {
      throw StateError(
        'found errors parsing build configs: ${errors.join('\n')}',
      );
    }

    final selectedField = await _fzf(fields);

    final gclientSynxExitCode = await (await io.Process.start(
      'gclient',
      const <String>['sync'],
      workingDirectory: engine.path,
      mode: io.ProcessStartMode.inheritStdio,
    ))
        .exitCode;
    if (gclientSynxExitCode != 0) {
      throw Exception('gclient sync failed');
    }

    final fieldTuple = selectedField.split(fieldSeparator);
    final targetName = fieldTuple[0];
    final buildName = fieldTuple[1];
    final build = configs[targetName]!.builds.firstWhere((build) {
      return build.name == buildName;
    });
    await _gn(build.gn, engine);
    await _ninja(build.ninja, engine);
    print('done');
    return 0;
  }

  Future<void> _gn(List<String> args, Directory engine) async {
    final gn = engine.childDirectory('tools').childFile('gn').path;
    final gnArgs = <String>[...args, '--no-goma']; // TODO handle goma
    print('starting gn $gn ${gnArgs.join(' ')}');
    final gnProcess = await io.Process.start(
      gn,
      gnArgs,
      mode: io.ProcessStartMode.inheritStdio,
    );
    final gnExit = await gnProcess.exitCode;
    if (gnExit != 0) {
      throw Exception('gn failed');
    }
  }

  Future<void> _ninja(BuildNinja ninja, Directory engine) async {
    final args = <String>[
      '-C',
      engine.parent.childDirectory('out').childDirectory(ninja.config).path,
      // TODO -j
      ...(ninja.targets),
    ];
    final ninjaProcess = await io.Process.start(
      'ninja',
      args,
      mode: io.ProcessStartMode.inheritStdio,
    );

    print('starting ninja ${args.join(' ')}');
    final ninjaExit = await ninjaProcess.exitCode;
    if (ninjaExit != 0) {
      throw Exception('ninja failed');
    }
    print('ninja finished');
  }
}

Future<String> _fzf(List<String> input) async {
  final process = await io.Process.start('fzf', const <String>[]);
  String? selectedField;
  final stdoutSub = process.stdout
      .transform(const convert.Utf8Decoder())
      .transform(const convert.LineSplitter())
      .listen((String line) {
    if (selectedField != null) {
      throw StateError(
        '''
got multiple STDOUT lines:
Already have: "$selectedField"
Got: "$line"''',
      );
    }
    selectedField = line;
  });
  final stderrSub =
      process.stderr.listen((List<int> bytes) => io.stderr.add(bytes));
  process.stdin.add(input.join('\n').codeUnits);
  await Future.wait<void>(<Future<void>>[
    stdoutSub.asFuture<void>(),
    stderrSub.asFuture<void>(),
    process.exitCode,
  ]);
  if (selectedField == null) {
    // this probably means user quit fzf with ESC
    throw StateError('Never received any STDOUT from fzf');
  }
  return selectedField!;
}
