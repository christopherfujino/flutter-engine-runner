import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:engine_build_configs/engine_build_configs.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'fzf.dart';

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
    final loader = BuildConfigLoader(
      buildConfigsDir: ciBuilderPath,
    );
    final configs = loader.configs;

    if (loader.errors.isNotEmpty) {
      throw StateError(
        'found errors parsing build configs: ${loader.errors.join('\n')}',
      );
    }

    final targetName = await fzfSingle(configs.keys);
    final config = configs[targetName]!;
    final buildName = await fzfSingle(config.builds.map((build) => build.name));
    final build = config.builds.firstWhere((build) => build.name == buildName);
    final ninjaTargetNames = await fzfMulti(build.ninja.targets);

    print('You chose $targetName -> $buildName -> $ninjaTargetNames');

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

    await _gn(build.gn, engine);
    await _ninja(ninjaTargetNames, build.ninja, engine);
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

  Future<void> _ninja(List<String> targets, BuildNinja ninja, Directory engine) async {
    final args = <String>[
      '-C',
      engine.parent.childDirectory('out').childDirectory(ninja.config).path,
      // TODO -j
      ...targets,
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
  }
}
