import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

class Manifest {
  static Future<void> export(
    String packPath,
    String packName,
    List<String> nameTags,
  ) async {
    final uuid = Uuid();
    final headerUuid = uuid.v4();
    final moduleUuid = uuid.v4();

    final manifestData = {
      "format_version": 2,
      "header": {
        "description":
            "Structura block overlay pack, created by \u00A75DrAv0011\u00A7r, \u00A79FondUnicycle\u00A7r and \u00A75RavinMaddHatter\u00A7r. Ported to Android by \u00A76sudo-carl\u00A7r.",
        "name": "$packName Resource Pack",
        "uuid": headerUuid,
        "version": [1, 0, 0],
        "min_engine_version": [1, 16, 0],
      },
      "modules": [
        {
          "description": "Structura Generated Pack",
          "type": "resources",
          "uuid": moduleUuid,
          "version": [1, 0, 0],
        },
      ],
    };

    final file = File('$packPath/manifest.json');
    await file.writeAsString(
      JsonEncoder.withIndent('  ').convert(manifestData),
    );
  }
}
