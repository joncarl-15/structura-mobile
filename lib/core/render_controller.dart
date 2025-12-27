import 'dart:convert';
import 'dart:io';

class RenderController {
  final Map<String, dynamic> _rc = {
    "format_version": "1.8.0",
    "render_controllers": {},
  };
  final String _rcName = "controller.render.armor_stand.ghost_blocks";

  String _geometry = "Geometry.default";
  String _textures = "Texture.default";

  RenderController() {
    _rc["render_controllers"][_rcName] = <String, dynamic>{
      "materials": [
        {"*": "Material.ghost_blocks"},
      ],
    };
  }

  void addModel(String nameRaw) {
    String name = nameRaw.replaceAll(" ", "_").toLowerCase();
    String geoTarget = "Geometry.ghost_blocks_$name";
    String texTarget = "Texture.ghost_blocks_$name";
    String geoFallback = _geometry;
    String texFallback = _textures;

    String condition = "query.get_name == '$nameRaw'";
    // If this is the start of the chain, make it the default for unnamed entities too
    if (_geometry == "Geometry.default") {
      condition += " || query.get_name == ''";
    }

    _geometry = "$condition ? $geoTarget : ($geoFallback)";
    _textures = "$condition ? $texTarget : ($texFallback)";
  }

  Future<void> export(String packPath) async {
    _rc["render_controllers"][_rcName]["geometry"] = _geometry;
    _rc["render_controllers"][_rcName]["textures"] = [_textures];

    final file = File(
      '$packPath/render_controllers/armor_stand.ghost_blocks.render_controllers.json',
    );
    await file.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_rc));
  }
}
