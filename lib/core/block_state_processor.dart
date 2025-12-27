import 'dart:convert';
import 'package:flutter/services.dart';

class BlockStateProcessor {
  Map<String, dynamic> nbtDefs = {};

  Future<void> init() async {
    try {
      final data = await rootBundle.loadString('assets/lookups/nbt_defs.json');
      nbtDefs = jsonDecode(data);
    } catch (e) {
      print("Failed to load nbt_defs.json: $e");
      // Fallback critical map
      nbtDefs = {
        "minecraft:direction": "rot",
        "minecraft:facing_direction": "rot",
        "weirdo_direction": "rot",
        "facing_direction": "rot",
        "direction": "rot",
        "upside_down_bit": "top",
        "upper_block_bit": "top",
        "top_slot_bit": "top",
        "open_bit": "open_bit",
        "data": "data",
        "stone_brick_type": "variant",
        "wood_type": "variant",
      };
    }
  }

  Map<String, dynamic> process(Map<String, dynamic> block) {
    dynamic rot;
    bool top = false;
    bool openBit = false;
    int data = 0;
    dynamic variant = "default";

    final states = block["states"] as Map<String, dynamic>? ?? {};

    // Iterate keys in NBT defs
    for (var key in nbtDefs.keys) {
      if (!states.containsKey(key)) continue;

      final val = states[key];
      final defType = nbtDefs[key];

      if (defType == "variant") {
        variant = [key, val];
      } else if (defType == "rot") {
        rot = val; // Assuming val is int or string from NbtReader
      } else if (defType == "top") {
        top = _toBool(val);
      } else if (defType == "open_bit") {
        openBit = _toBool(val);
      } else if (defType == "data") {
        data = _toInt(val);
      }

      if (key == "rail_direction") {
        data = _toInt(val);
        if (states.containsKey("rail_data_bit")) {
          // Complex logic, skipping fine details for MVP unless rail issue reported.
        }
      }
    }

    // Wood Type logic
    if (states.containsKey("wood_type")) {
      var wType = states["wood_type"];
      if (block["name"] == "minecraft:wood") {
        if (_toBool(states["stripped_bit"])) {
          wType = "${wType}_stripped";
        }
        variant = ["wood", wType];
      } else {
        variant = ["wood_type", wType];
      }
    }

    return {
      "rot": rot,
      "top": top,
      "variant": variant,
      "open_bit": openBit,
      "data": data,
    };
  }

  bool _toBool(dynamic val) {
    if (val is bool) return val;
    if (val is int) return val != 0;
    return val.toString().toLowerCase() == 'true';
  }

  int _toInt(dynamic val) {
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }
}
