import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class AnimationClass {
  Map<String, dynamic> defaultSize = {
    "format_version": "1.8.0",
    "animations": {
      "animation.armor_stand.ghost_blocks.scale": {
        "loop": true,
        "bones": {
          "ghost_blocks": {"scale": 16.0},
        },
      },
    },
  };

  Map<String, dynamic>? sizing;

  final Map<int, String> poses = {
    0: "animation.armor_stand.default_pose",
    1: "animation.armor_stand.no_pose",
    2: "animation.armor_stand.solemn_pose",
    3: "animation.armor_stand.athena_pose",
    4: "animation.armor_stand.brandish_pose",
    5: "animation.armor_stand.honor_pose",
    6: "animation.armor_stand.entertain_pose",
    7: "animation.armor_stand.salute_pose",
    8: "animation.armor_stand.riposte_pose",
    9: "animation.armor_stand.zombie_pose",
    10: "animation.armor_stand.cancan_a_pose",
    11: "animation.armor_stand.cancan_b_pose",
    12: "animation.armor_stand.hero_pose",
  };

  Future<void> init(String refResourcePack) async {
    // Load armor_stand.animation.json from vanilla assets
    final data = await rootBundle.loadString(
      '$refResourcePack/animations/armor_stand.animation.json',
    );
    sizing = jsonDecode(data);
  }

  void insertLayer(int y) {
    if (sizing == null) return;
    String name = "layer_$y";

    // Cycle through 12 poses
    for (int i = 0; i < 12; i++) {
      if (y % 12 != i) {
        String poseName = poses[i + 1]!; // poses 1..12
        if (sizing!["animations"].containsKey(poseName)) {
          if (sizing!["animations"][poseName]["bones"] == null) {
            sizing!["animations"][poseName]["bones"] = {};
          }
          sizing!["animations"][poseName]["bones"][name] = {"scale": 0.0};
        }
      }
    }
  }

  Future<void> export(String packPath) async {
    // 1. Export modified armor_stand.animation.json
    final aniFile = File('$packPath/animations/armor_stand.animation.json');
    await aniFile.create(recursive: true);
    await aniFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(sizing),
    );

    // 2. Export scale animation
    final scaleFile = File(
      '$packPath/animations/armor_stand.ghost_blocks.scale.animation.json',
    );
    await scaleFile.create(recursive: true);
    await scaleFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultSize),
    );
  }
}
