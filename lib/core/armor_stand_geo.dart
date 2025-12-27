import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ArmorStandGeo {
  final String name;
  double alpha = 0.4;
  List<int> offsets = [0, 0, 0];
  List<int> size = [64, 64, 64];
  final String refResourcePack = "assets/vanilla_pack";

  Map<String, dynamic> blocksDef = {};
  Map<String, dynamic> terrainTexture = {};
  Map<String, dynamic> blockRotations = {};
  Map<String, dynamic> blockVariants = {};
  Map<String, dynamic> defs = {};
  Map<String, dynamic> blockShapes = {};
  Map<String, dynamic> blockUv = {};

  // Internal state
  Map<String, dynamic> stand = {};
  Map<String, dynamic> geometry = {};
  Map<String, dynamic> blocks = {};
  List<String> layers = [];
  Map<String, int> uvMap = {};
  img.Image? uvArray;

  List<String> excluded = ["air", "structure_block"];

  ArmorStandGeo(this.name);

  Future<void> init() async {
    // Load JSON definitions from assets
    blocksDef = jsonDecode(
      await rootBundle.loadString('$refResourcePack/blocks.json'),
    );
    terrainTexture = jsonDecode(
      await rootBundle.loadString(
        '$refResourcePack/textures/terrain_texture.json',
      ),
    );

    blockRotations = jsonDecode(
      await rootBundle.loadString('assets/lookups/block_rotation.json'),
    );
    blockVariants = jsonDecode(
      await rootBundle.loadString('assets/lookups/variants.json'),
    );
    defs = jsonDecode(
      await rootBundle.loadString('assets/lookups/block_definition.json'),
    );
    blockShapes = jsonDecode(
      await rootBundle.loadString('assets/lookups/block_shapes.json'),
    );
    blockUv = jsonDecode(
      await rootBundle.loadString('assets/lookups/block_uv.json'),
    );

    _standInit();
  }

  void _standInit() {
    stand["format_version"] = "1.16.0";
    geometry = {};
    geometry["description"] = {
      "identifier": "geometry.armor_stand.ghost_blocks_${name.toLowerCase()}",
      "texture_width": 1,
      "visible_bounds_offset": [0.0, 1.5, 0.0],
      "visible_bounds_width": 5120,
      "visible_bounds_height": 5120,
    };
    geometry["bones"] = <dynamic>[
      {
        "name": "ghost_blocks",
        "pivot": [-8, 0, 8],
      },
    ];
    stand["minecraft:geometry"] = [geometry];
  }

  void addModelGeo(
    String modelName,
    List<int> modelSize,
    List<int> modelOffsets,
  ) {
    this.size = modelSize;
    this.offsets = [modelOffsets[0] + 8, modelOffsets[1], modelOffsets[2] + 7];
  }

  void makeLayer(int y) {
    String layerName = "layer_$y";
    if (!layers.contains(layerName)) {
      layers.add(layerName);
      (geometry["bones"] as List).add({
        "name": layerName,
        "parent": "ghost_blocks",
      });
    }
  }

  Future<void> makeBlock(
    int x,
    int y,
    int z,
    Map<String, dynamic> block,
    String modelName, {
    dynamic variant = "default",
    dynamic rot,
    bool top = false,
    bool open = false,
    int data = 0,
  }) async {
    String blockName = block["name"].toString().replaceFirst("minecraft:", "");
    String? blockType = defs[blockName];

    if (blockType == null) {
      if (blockName.endsWith("_stairs")) {
        blockType = "stairs";
      } else {
        return;
      }
    }

    if (blockType == "ignore") return;

    String ghostBlockName = "block_${x}_${y}_${z}";
    Map<String, dynamic> blockEntry = {};
    blockEntry["name"] = ghostBlockName;
    String layerName = "layer_${y}";
    blockEntry["parent"] = layerName;

    String shapeVariant = "default";
    if (variant is List) {}

    // Override shape for stairs/slabs if needed based on 'top'
    if (open && blockShapes[blockType].containsKey("open")) {
      shapeVariant = "open";
    } else if (top && blockShapes[blockType].containsKey("top")) {
      shapeVariant = "top";
    }

    if (!blockShapes.containsKey(blockType)) {
      print("Missing shape for $blockType");
      return;
    }

    Map<String, dynamic> shapes =
        blockShapes[blockType][shapeVariant] ??
        blockShapes[blockType]["default"];

    if (blockShapes[blockType].containsKey(data.toString())) {
      shapeVariant = data.toString();
      shapes = blockShapes[blockType][data.toString()];
    }

    // Pivot
    List<dynamic> center = shapes["center"];
    blockEntry["pivot"] = [
      center[0] - (x + offsets[0]),
      y + center[1] + offsets[1],
      z + center[2] + offsets[2],
    ];
    blockEntry["inflate"] = -0.03;

    // Cubes
    blockEntry["cubes"] = [];
    List<dynamic> sizes = shapes["size"];

    for (int i = 0; i < sizes.length; i++) {
      // UV Mapping
      Map<String, dynamic> uvData = await _blockNameToUv(
        blockName,
        variant,
        shapeVariant,
        i,
        data,
      );

      // Block geometry
      Map<String, dynamic> cube = {};

      List<double> origin = [
        -1.0 * (x + offsets[0]),
        (y + 0.0 + offsets[1]),
        (z + 0.0 + offsets[2]),
      ];
      // Add shape specific offsets
      if (shapes.containsKey("offsets")) {
        origin[0] += shapes["offsets"][i][0];
        origin[1] += shapes["offsets"][i][1];
        origin[2] += shapes["offsets"][i][2];
      }
      cube["origin"] = origin;
      cube["size"] = sizes[i];

      if (shapes.containsKey("rotation")) {
        cube["rotation"] = shapes["rotation"][i];
      }

      // Get block_uv data for this block type
      Map<String, dynamic>? blockUvData;
      if (blockUv.containsKey(blockType)) {
        // Check for shape variant specific UV data
        if (blockUv[blockType].containsKey(shapeVariant)) {
          blockUvData = blockUv[blockType][shapeVariant];
        } else if (blockUv[blockType].containsKey("default")) {
          blockUvData = blockUv[blockType]["default"];
        }
      }

      // Determine UV index (for multi-part blocks)
      int uvIdx = 0;
      if (blockUvData != null && blockUvData.containsKey("uv_sizes")) {
        Map<String, dynamic> uvSizes = blockUvData["uv_sizes"];
        if (uvSizes.containsKey("up") && uvSizes["up"] is List) {
          if ((uvSizes["up"] as List).length > i) {
            uvIdx = i;
          }
        }
      }

      // Calculate UV Sizes and Offsets per face
      Map<String, dynamic> finalUv = {};

      // uvData contains keys like "north" with "uv": [0, y]
      uvData.forEach((face, data) {
        if (data is Map && data.containsKey("uv")) {
          List<dynamic> uvOrigin = List.from(data["uv"]);
          List<double> uvSize = [1.0, 1.0];

          // Apply block_uv data if available
          if (blockUvData != null) {
            // Apply UV offset from block_uv.json
            if (blockUvData.containsKey("offset") &&
                blockUvData["offset"].containsKey(face) &&
                blockUvData["offset"][face] is List &&
                (blockUvData["offset"][face] as List).length > uvIdx) {
              List<dynamic> offset = blockUvData["offset"][face][uvIdx];
              uvOrigin[0] = (uvOrigin[0] as num) + (offset[0] as num);
              uvOrigin[1] = (uvOrigin[1] as num) + (offset[1] as num);
            }

            // Apply UV size from block_uv.json
            if (blockUvData.containsKey("uv_sizes") &&
                blockUvData["uv_sizes"].containsKey(face) &&
                blockUvData["uv_sizes"][face] is List &&
                (blockUvData["uv_sizes"][face] as List).length > uvIdx) {
              List<dynamic> sizeData = blockUvData["uv_sizes"][face][uvIdx];
              uvSize = [
                (sizeData[0] as num).toDouble(),
                (sizeData[1] as num).toDouble(),
              ];
            }
          }

          finalUv[face] = {"uv": uvOrigin, "uv_size": uvSize};
        }
      });

      cube["uv"] = finalUv;
      (blockEntry["cubes"] as List).add(cube);
    }

    // Apply Rotation
    if (rot != null && blockRotations.containsKey(blockType)) {
      // rot can be int or string depending on NBT parser, convert to string for JSON key
      String rotKey = rot.toString();
      if (blockRotations[blockType].containsKey(rotKey)) {
        blockEntry["rotation"] = blockRotations[blockType][rotKey];

        // hardcoded it here since the json files do tend to get a little quirky at night haur haur hau haur haur
        if (blockType == "stairs") {
          final correctStairsRotation = {
            "0": [0, -90, 0],
            "1": [0, 90, 0],
            "2": [0, 0, 0],
            "3": [0, 180, 0],
          };
          blockEntry["rotation"] = correctStairsRotation[rotKey];
        }
      }
    }

    blocks[ghostBlockName] = blockEntry;
  }

  Future<Map<String, dynamic>> _blockNameToUv(
    String blockName,
    dynamic variant,
    String shapeVariant,
    int index, [
    int data = 0,
  ]) async {
    if (excluded.contains(blockName)) return {};

    Map<String, String> textureFiles = _getBlockTexturePaths(
      blockName,
      variant,
      data,
    );

    Map<String, dynamic> tempUv = {};

    for (var side in textureFiles.keys) {
      String textureName = textureFiles[side]!;

      if (!uvMap.containsKey(textureName)) {
        await _extendUvImage(textureName);
        uvMap[textureName] = uvMap.length;
      }

      // Return logical unit index for UV (0, 1, 2...) instead of pixel offset
      tempUv[side] = {
        "uv": [0, uvMap[textureName]! * 1],
      };
    }
    return tempUv;
  }

  Future<void> _extendUvImage(String textureName) async {
    String cleanPath = textureName;
    if (!cleanPath.endsWith(".png")) cleanPath += ".png";

    try {
      final data = await rootBundle.load('$refResourcePack/$cleanPath');
      final image = img.decodePng(data.buffer.asUint8List())!;

      // Resize or force to 16x16 to ensure high quality "heavy" texture
      img.Image processed = image;
      if (image.width != 16 || image.height != 16) {
        processed = img.copyResize(image, width: 16, height: 16);
      }

      if (uvArray == null) {
        // Initialize with high res 16px width
        uvArray = img.Image(width: 16, height: 16, numChannels: 4);
        uvArray = processed;
      } else {
        // Extend by 16 pixels height
        int newHeight = uvArray!.height + 16;
        final newImage = img.Image(
          width: 16,
          height: newHeight,
          numChannels: 4,
        );

        img.compositeImage(newImage, uvArray!, dstX: 0, dstY: 0);
        img.compositeImage(newImage, processed, dstX: 0, dstY: uvArray!.height);

        uvArray = newImage;
      }
    } catch (e) {
      print("Failed to load texture $cleanPath: $e");
    }
  }

  Map<String, String> _getBlockTexturePaths(
    String blockName,
    dynamic variant, [
    int data = 0,
  ]) {
    if (!blocksDef.containsKey(blockName)) {
      Map<String, String> aliases = {
        "stone_bricks": "stonebrick",
        "stone_brick": "stonebrick",
        "stone_brick_stairs": "stonebrick",
        "stone_stairs": "cobblestone",
        "mossy_stone_brick_stairs": "stonebrick",
      };

      if (aliases.containsKey(blockName)) {
        blockName = aliases[blockName]!;
      }

      if (!blocksDef.containsKey(blockName)) return {};
    }
    final def = blocksDef[blockName];
    dynamic textureLayout = def["textures"];
    Map<String, String> textures = {};

    if (textureLayout is String) {
      textures["east"] = textureLayout;
      textures["west"] = textureLayout;
      textures["north"] = textureLayout;
      textures["south"] = textureLayout;
      textures["up"] = textureLayout;
      textures["down"] = textureLayout;
    } else if (textureLayout is Map) {
      textures["east"] = textureLayout["east"] ?? textureLayout["side"];
      textures["west"] = textureLayout["west"] ?? textureLayout["side"];
      textures["north"] = textureLayout["north"] ?? textureLayout["side"];
      textures["south"] = textureLayout["south"] ?? textureLayout["side"];
      textures["up"] = textureLayout["up"];
      textures["down"] = textureLayout["down"];
    }

    Map<String, String> resolved = {};
    if (!terrainTexture.containsKey("texture_data")) return {};

    final textureData = terrainTexture["texture_data"];

    textures.forEach((key, val) {
      if (val != null && textureData.containsKey(val)) {
        final dataEntry = textureData[val]["textures"];
        if (dataEntry is String) {
          resolved[key] = dataEntry;
        } else if (dataEntry is List) {
          if (variant is List && variant.length == 2 && variant[1] is int) {
            // Variant explicit list e.g. ["wood_type", 2]
            int idx = variant[1];
            if (idx < dataEntry.length)
              resolved[key] = dataEntry[idx];
            else
              resolved[key] = dataEntry[0];
          } else if (variant is int) {
            // Variant is explicit int index
            if (variant < dataEntry.length)
              resolved[key] = dataEntry[variant];
            else
              resolved[key] = dataEntry[0];
          } else if ((variant == "default" || variant == null) && data > 0) {
            // Fallback to data value if variant is default (fixes Stone Bricks)
            if (data < dataEntry.length)
              resolved[key] = dataEntry[data];
            else
              resolved[key] = dataEntry[0];
          } else {
            // Default 0
            resolved[key] = dataEntry[0] as String;
          }
        } else if (dataEntry is Map) {
          if (dataEntry.containsKey("path")) {
            resolved[key] = dataEntry["path"];
          }
        }
      }
    });
    return resolved;
  }

  static Future<void> exportLargerRender(String packFolder) async {
    final Map<String, dynamic> largerRender = {
      "format_version": "1.12.0",
      "minecraft:geometry": [
        {
          "description": {
            "identifier": "geometry.armor_stand.larger_render",
            "texture_width": 64.0,
            "texture_height": 64.0,
            "visible_bounds_offset": [0.0, 1.5, 0.0],
            "visible_bounds_width": 5120,
            "visible_bounds_height": 5120,
          },
          "bones": [
            {
              "name": "baseplate",
              "cubes": [
                {
                  "origin": [-6.0, 0.0, -6.0],
                  "size": [12.0, 1.0, 12.0],
                  "uv": [0.0, 32.0],
                },
              ],
            },
            {
              "name": "waist",
              "parent": "baseplate",
              "pivot": [0.0, 12.0, 0.0],
            },
            {
              "name": "body",
              "parent": "waist",
              "pivot": [0.0, 24.0, 0.0],
              "cubes": [
                {
                  "origin": [-6.0, 21.0, -1.5],
                  "size": [12.0, 3.0, 3.0],
                  "uv": [0.0, 26.0],
                },
                {
                  "origin": [-3.0, 14.0, -1.0],
                  "size": [2.0, 7.0, 2.0],
                  "uv": [16.0, 0.0],
                },
                {
                  "origin": [1.0, 14.0, -1.0],
                  "size": [2.0, 7.0, 2.0],
                  "uv": [48.0, 16.0],
                },
                {
                  "origin": [-4.0, 12.0, -1.0],
                  "size": [8.0, 2.0, 2.0],
                  "uv": [0.0, 48.0],
                },
              ],
            },
            {
              "name": "head",
              "parent": "body",
              "pivot": [0.0, 24.0, 0.0],
              "cubes": [
                {
                  "origin": [-1.0, 24.0, -1.0],
                  "size": [2.0, 7.0, 2.0],
                  "uv": [0.0, 0.0],
                },
              ],
            },
            {
              "name": "hat",
              "parent": "head",
              "pivot": [0.0, 24.0, 0.0],
              "cubes": [
                {
                  "origin": [-4.0, 24.0, -4.0],
                  "size": [8.0, 8.0, 8.0],
                  "uv": [32.0, 0.0],
                },
              ],
            },
            {
              "name": "leftarm",
              "parent": "body",
              "mirror": true,
              "pivot": [5.0, 22.0, 0.0],
              "cubes": [
                {
                  "origin": [5.0, 12.0, -1.0],
                  "size": [2.0, 12.0, 2.0],
                  "uv": [32.0, 16.0],
                },
              ],
            },
            {
              "name": "leftitem",
              "parent": "leftarm",
              "pivot": [6.0, 15.0, 1.0],
            },
            {
              "name": "leftleg",
              "parent": "body",
              "mirror": true,
              "pivot": [1.9, 12.0, 0.0],
              "cubes": [
                {
                  "origin": [0.9, 1.0, -1.0],
                  "size": [2.0, 11.0, 2.0],
                  "uv": [40.0, 16.0],
                },
              ],
            },
            {
              "name": "rightarm",
              "parent": "body",
              "pivot": [-5.0, 22.0, 0.0],
              "cubes": [
                {
                  "origin": [-7.0, 12.0, -1.0],
                  "size": [2.0, 12.0, 2.0],
                  "uv": [24.0, 0.0],
                },
              ],
            },
            {
              "name": "rightitem",
              "parent": "rightarm",
              "pivot": [-6.0, 15.0, 1.0],
            },
            {
              "name": "rightleg",
              "parent": "body",
              "pivot": [-1.9, 12.0, 0.0],
              "cubes": [
                {
                  "origin": [-2.9, 1.0, -1.0],
                  "size": [2.0, 11.0, 2.0],
                  "uv": [8.0, 0.0],
                },
              ],
            },
          ],
        },
      ],
    };

    final file = File(
      '$packFolder/models/entity/armor_stand.larger_render.geo.json',
    );
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(largerRender));
  }

  Future<void> export(String packFolder) async {
    (geometry["bones"] as List).addAll(blocks.values);
    // Use logical unit height (number of blocks), not pixels
    geometry["description"]["texture_height"] = uvMap.length * 1;

    final file = File(
      '$packFolder/models/entity/armor_stand.ghost_blocks_${name.toLowerCase()}.geo.json',
    );
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(stand));

    if (uvArray != null) {
      // Apply alpha transparency (uvArray is full 16xN resolution)
      final processedImage = _applyAlpha(uvArray!);

      final texFile = File(
        '$packFolder/textures/entity/ghost_blocks_${name.toLowerCase()}.png',
      );
      await texFile.create(recursive: true);
      await texFile.writeAsBytes(img.encodePng(processedImage));
    }
  }

  img.Image _applyAlpha(img.Image source) {
    // Create a copy of the image to avoid modifying the original
    final result = img.Image.from(source);

    // Apply alpha to all pixels using iterator for better performance and correctness
    for (final pixel in result) {
      final currentAlpha = pixel.a;

      // Only modify non-fully-transparent pixels
      if (currentAlpha > 0) {
        // Apply global alpha multiplier
        pixel.a = (currentAlpha * alpha).round().clamp(0, 255);
      }
    }

    return result;
  }
}
