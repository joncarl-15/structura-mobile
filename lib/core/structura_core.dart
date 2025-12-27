import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'armor_stand_geo.dart';
import 'manifest.dart';
import 'structure_reader.dart';

import 'client_entity.dart';
import 'render_controller.dart';
import 'animation_class.dart';

import 'block_state_processor.dart';

class StructuraCore {
  final String packName;
  late Directory packDir;
  final Map<String, dynamic> structureFiles = {};
  ArmorStandGeo? armorStandEntity;
  ClientEntity? clientEntity;
  RenderController? renderController;
  AnimationClass? animationClass;
  BlockStateProcessor? blockStateProcessor;
  double opacity = 0.8;
  String iconPath = "assets/lookups/pack_icon.png";

  StructuraCore(this.packName);

  Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    packDir = Directory('${docsDir.path}/$packName');
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }
    await packDir.create(recursive: true);

    // Initialize helpers
    armorStandEntity = ArmorStandGeo(packName);
    clientEntity = ClientEntity();
    renderController = RenderController();
    animationClass = AnimationClass();
    blockStateProcessor = BlockStateProcessor();

    await armorStandEntity!.init();
    await animationClass!.init("assets/vanilla_pack");
    await blockStateProcessor!.init();
  }

  void setOpacity(double opacity) {
    this.opacity = opacity;
    armorStandEntity?.alpha = opacity;
  }

  void addModel(String name, String filePath) {
    structureFiles[name] = {
      "file": filePath,
      "offsets": [0, 0, 0],
    };
  }

  void setModelOffset(String name, List<int> offset) {
    structureFiles[name]["offsets"] = offset;
  }

  Future<String> generateWithNametags() async {
    int totalBlocks = 0;
    for (var modelName in structureFiles.keys) {
      final fileData = structureFiles[modelName];
      List<int> offset = fileData["offsets"] ?? [0, 0, 0];

      // Copy mcstructure file
      final sourceFile = File(fileData["file"]);
      final destPath = "${packDir.path}/$modelName.mcstructure";
      await sourceFile.copy(destPath);

      // Process structure
      final structReader = StructureReader(fileData["file"]);
      await structReader.init();

      // Add blocks to geometry
      await _addBlocksToGeo(structReader, modelName, offset);

      // Update entity and helper definitions
      clientEntity!.addModel(modelName);
      renderController!.addModel(modelName);

      // Count blocks for debug
      final size = structReader.getSize();
      for (int y = 0; y < size[1]; y++) {
        totalBlocks += structReader.getLayerBlocks(y).length;
      }

      // Export current state of armorstand
      await armorStandEntity!.export(packDir.path);
    }
    return "Processed ${structureFiles.length} models. Total blocks: $totalBlocks";
  }

  Future<void> _addBlocksToGeo(
    StructureReader structReader,
    String modelName,
    List<int> offset,
  ) async {
    final size = structReader.getSize();

    // Update armorstand geo with new model
    armorStandEntity!.addModelGeo(modelName, size, offset);

    // Iterate through layers (Y)
    for (int y = 0; y < size[1]; y++) {
      final nonAirBlocks = structReader.getLayerBlocks(y);
      if (nonAirBlocks.isEmpty) continue;

      armorStandEntity!.makeLayer(y);
      animationClass!.insertLayer(y);

      for (var loc in nonAirBlocks) {
        int x = loc[0];
        int z = loc[1];
        final block = structReader.getBlock(x, y, z);

        // Process block states
        final props = blockStateProcessor?.process(block);

        // Add to material list
        String blockName = block["name"].toString().replaceFirst(
          "minecraft:",
          "",
        );
        if (props?["variant"] != null && props?["variant"] != "default") {
          if (props!["variant"] is List) {
            blockName += " [${props["variant"][1]}]";
          } else {
            blockName += " [${props["variant"]}]";
          }
        }
        materialList.update(blockName, (value) => value + 1, ifAbsent: () => 1);

        if (blockName.contains("stairs")) {
          print(
            "DEBUG_BLOCK: $blockName | Original: ${block["states"]} | Processed: $props",
          );
        }

        await armorStandEntity!.makeBlock(
          x,
          y,
          z,
          block,
          modelName,
          variant: props?["variant"] ?? "default",
          rot: props?["rot"],
          top: props?["top"] ?? false,
          open: props?["open_bit"] ?? false,
          data: props?["data"] ?? 0,
        );
      }
    }
  }

  Future<String> compilePack({bool makeLists = true}) async {
    // Generate JSONs
    await Manifest.export(packDir.path, packName, structureFiles.keys.toList());
    await clientEntity!.export(packDir.path);
    await renderController!.export(packDir.path);
    await animationClass!.export(packDir.path);
    await ArmorStandGeo.exportLargerRender(packDir.path);

    // Export Material List (conditional)
    if (makeLists) {
      await _exportMaterialList();
    }

    // Copy Icon
    final iconData = await rootBundle.load(iconPath);
    final iconFile = File("${packDir.path}/pack_icon.png");
    await iconFile.writeAsBytes(iconData.buffer.asUint8List());

    // Verify contents
    print("Packing directory: ${packDir.path}");
    if (await packDir.exists()) {
      await for (var entity in packDir.list(recursive: true)) {
        print("Found file: ${entity.path}");
      }
    } else {
      print("Pack directory does not exist!");
    }

    // Zip Conversion
    var encoder = ZipFileEncoder();
    encoder.create('${packDir.path}.mcpack');

    if (await packDir.exists()) {
      await for (var entity in packDir.list(recursive: true)) {
        if (entity is File) {
          String relativePath = p.relative(entity.path, from: packDir.path);
          print("Zipping: $relativePath");
          await encoder.addFile(entity, relativePath);
        }
      }
    }

    encoder.close();

    return '${packDir.path}.mcpack';
  }

  Future<void> _exportMaterialList() async {
    // Save materials.txt
    final filePath = '${packDir.path}_materials.txt';
    print("DEBUG: Exporting material list to: $filePath");
    print("DEBUG: Material list has ${materialList.length} items");

    final file = File(filePath);
    final buffer = StringBuffer();
    buffer.writeln("Material List for $packName");
    buffer.writeln("============================");

    // Sort by count descending
    final sortedKeys = materialList.keys.toList()
      ..sort((a, b) => materialList[b]!.compareTo(materialList[a]!));

    for (var key in sortedKeys) {
      buffer.writeln("${materialList[key]}\t$key");
    }

    await file.writeAsString(buffer.toString());
    print("DEBUG: Material list exported successfully to: $filePath");
  }

  final Map<String, int> materialList = {};

  Future<String> generatePack() async {
    materialList.clear();
    await init();
    await generateWithNametags();
    return await compilePack();
  }
}
