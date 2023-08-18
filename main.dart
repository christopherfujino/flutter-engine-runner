import 'dart:io' as io;
import 'dart:convert' as convert;

import 'package:file/file.dart';
import 'package:file/local.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw Exception('Usage: dart main.dart /path/to/engine');
  }
  const fs = LocalFileSystem();
  final engine = fs.directory(args.first);
  final ciBuilderPath = engine.childDirectory('ci').childDirectory('builders');
  if (!ciBuilderPath.existsSync()) {
    throw Exception('Expected ${ciBuilderPath.path} to exist');
  }
  final builderConfigs =
      ciBuilderPath.listSync().where((io.FileSystemEntity entity) {
    return entity is io.File && entity.path.endsWith('.json');
  }).map<BuilderConfig>((io.FileSystemEntity entity) {
    final file = entity as io.File;
    return BuilderConfig.fromJson(
        file.readAsStringSync(), fs.path.basename(file.path), engine);
  });
  builderConfigs.forEach(print);

  // TODO cache this
  //final gclientSynxExitCode = await (await io.Process.start(
  //  'gclient',
  //  const <String>['sync'],
  //  workingDirectory: engine.path,
  //  mode: io.ProcessStartMode.inheritStdio,
  //))
  //    .exitCode;
  //if (gclientSynxExitCode != 0) {
  //  throw Exception('gclient sync failed');
  //}
  await builderConfigs.first.builds.first.run();
  print('done');
}

class BuilderConfig {
  BuilderConfig.fromJson(String src, String name, Directory engine) {
    this.name = name;
    final json = convert.jsonDecode(src);
    builds = (json['builds'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map<Build>((Map<String, Object?> map) => Build.fromJson(map, engine))
        .toList();
  }

  late final String name;
  late final List<Build> builds;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln(name);
    for (final build in builds) {
      buffer.writeln(' -> ${build.name}');
    }
    return buffer.toString();
  }
}

class Build {
  Build.fromJson(Map<String, Object?> src, this.engine) {
    archives = (src['archives'] as List<Object?>?)
        ?.cast<Map<String, Object?>>()
        .map<Archive>((Map<String, Object?> map) => Archive.fromJson(map))
        .toList();

    gn = (src['gn'] as List<Object?>?)?.cast<String>();
    final ninjaMap = src['ninja'] as Map<String, Object?>?;
    if (ninjaMap != null) {
      final config = ninjaMap['config'] as String;
      final targets = (ninjaMap['targets'] as List<Object?>).cast<String>();
      ninja = (config: config, targets: targets);
    }
    name = src['name'] as String;
  }

  late final List<Archive>? archives;
  // TODO drone_dimensions
  // TODO gclient_custom_vars
  // TODO tests

  late final List<String>? gn;
  ({String config, List<String> targets})? ninja;
  late final String name;
  final Directory engine;

  Future<void> run() async {
    final gnProcess = await io.Process.start(
      engine.childDirectory('tools').childFile('gn').path,
      <String>[...gn!, '--no-goma'], // TODO handle goma
      mode: io.ProcessStartMode.inheritStdio,
    );
    final gnExit = await gnProcess.exitCode;
    if (gnExit != 0) {
      throw Exception('gn failed');
    }

    print('gn succeeded');

    await _ninja();
  }

  Future<void> _ninja() async {
    final args = <String>[
      '-C',
      engine.parent.childDirectory('out').childDirectory(ninja!.config).path,
      // TODO -j
      ...(ninja!.targets),
    ];
    final ninjaProcess = await io.Process.start('ninja', args, mode: io.ProcessStartMode.inheritStdio);

    print('starting ninja ${args.join(' ')}');
    final ninjaExit = await ninjaProcess.exitCode;
    if (ninjaExit != 0) {
      throw Exception('ninja failed');
    }
    print('ninja finished');
  }
}

class Archive {
  Archive.fromJson(Map<String, Object?> map) {
    name = map['name'] as String;
    type = map['type'] as String?;
    basePath = map['base_path'] as String;
    includePaths = (map['include_paths'] as List<Object?>).cast<String>();
  }

  late final String name;
  late final String? type;
  late final String basePath;
  late final List<String> includePaths;
}
