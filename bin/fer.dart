import 'dart:async';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:flutter_engine_runner/src/build_command.dart';

const fs = LocalFileSystem();

Future<void> main(List<String> args) async {
  _init();

  final runner = CommandRunner<int>(
    'fer',
    'Flutter Engine build Runner',
  )..addCommand(BuildCommand());

  final exitCode = (await runner.run(args))!;
  io.exit(exitCode);
}

void _init() {
  const requiredBinaries = <String>[
    'gclient',
    'ninja',
    'fzf',
  ];
  final errors = <String>[];

  for (final binary in requiredBinaries) {
    // TODO support Windows
    final result = io.Process.runSync('which', <String>[binary]);
    if (result.exitCode != 0) {
      errors.add('Required binary "$binary" does not exist on path');
    }
  }

  if (errors.isNotEmpty) {
    throw Exception(errors.join('\n'));
  }
}
