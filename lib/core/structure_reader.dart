import 'dart:io';
import 'nbt_helper.dart';

class StructureReader {
  final String filePath;
  NbtCompound? _nbt;
  List<int> _blockIndices = [];
  List<int> _size = [];
  List<Map<String, dynamic>> _palette = [];
  List<int> _cube = [];

  StructureReader(this.filePath);

  Future<void> init() async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final nbtReader = NbtReader(bytes);

    final rootTag = nbtReader.read();
    if (rootTag is NbtCompound) {
      _nbt = rootTag;
    } else {
      _nbt = NbtCompound({});
    }

    NbtCompound root = _nbt!;
    if (root.containsKey("")) {
      if (root[""] is NbtCompound) {
        root = root[""] as NbtCompound;
      }
    }

    // Parse Structure Data
    final structure = root.getCompound('structure');
    final blockIndicesList = structure.getList('block_indices');

    if (blockIndicesList.value.isNotEmpty) {
      final layer0 = blockIndicesList.value[0];
      if (layer0 is NbtList) {
        _blockIndices = layer0.value.map((e) {
          if (e is NbtInt) return e.value;
          return 0;
        }).toList();
      }
    }

    final sizeList = root.getList('size');
    _size = sizeList.value.map((e) {
      if (e is NbtInt) return e.value;
      return 0;
    }).toList();

    // Parse Palette
    final paletteTag = structure.getCompound('palette');
    final defaultPalette = paletteTag.getCompound('default');
    final blockPalette = defaultPalette.getList('block_palette');

    _palette = blockPalette.value.map<Map<String, dynamic>>((e) {
      if (e is NbtCompound) {
        final compound = e;
        Map<String, dynamic> blockMap = {};
        if (compound["name"] is NbtString) {
          blockMap['name'] = (compound["name"] as NbtString).value;
        } else {
          blockMap['name'] = "minecraft:air";
        }

        Map<String, dynamic> statesMap = {};
        if (compound["states"] is NbtCompound) {
          final states = compound["states"] as NbtCompound;
          for (var key in states.keys) {
            final val = states[key];
            if (val is NbtInt)
              statesMap[key] = val.value;
            else if (val is NbtByte)
              statesMap[key] = val.value;
            else if (val is NbtString)
              statesMap[key] = val.value;
          }
        }
        blockMap['states'] = statesMap;
        return blockMap;
      }
      return {"name": "minecraft:air", "states": {}};
    }).toList();

    _prepBlockMap();
  }

  void _prepBlockMap() {
    int indexOfAir = -1;
    for (int i = 0; i < _palette.length; i++) {
      if (_palette[i]['name'] == 'minecraft:air') {
        indexOfAir = i;
        break;
      }
    }

    _cube = List<int>.from(_blockIndices);

    for (int i = 0; i < _cube.length; i++) {
      _cube[i] += 1;
    }

    _palette.insert(0, {"name": "minecraft:air", "states": {}});

    if (indexOfAir != -1) {
      int target = indexOfAir + 1;
      for (int i = 0; i < _cube.length; i++) {
        if (_cube[i] == target) {
          _cube[i] = 0;
        }
      }
    }
  }

  List<int> getSize() => _size;

  Map<String, dynamic> getBlock(int x, int y, int z) {
    if (_size.length < 3) return _palette[0];

    int index = x * (_size[1] * _size[2]) + y * _size[2] + z;

    if (index < 0 || index >= _cube.length) return _palette[0];

    int paletteIndex = _cube[index];
    if (paletteIndex < 0 || paletteIndex >= _palette.length) return _palette[0];

    return _palette[paletteIndex];
  }

  List<List<int>> getLayerBlocks(int y) {
    List<List<int>> blocks = [];
    if (_size.length < 3) return blocks;

    for (int x = 0; x < _size[0]; x++) {
      for (int z = 0; z < _size[2]; z++) {
        int index = x * (_size[1] * _size[2]) + y * _size[2] + z;
        if (index < _cube.length && _cube[index] > 0) {
          blocks.add([x, z]);
        }
      }
    }
    return blocks;
  }
}
