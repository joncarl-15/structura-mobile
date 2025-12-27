import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/structura_core.dart';
import 'widgets/update_dialog.dart';
import 'core/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UpdateService().init();
  runApp(const StructuraApp());
}

class StructuraApp extends StatelessWidget {
  const StructuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Structura Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _fileController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  double _opacity = 0.4;
  bool _isGenerating = false;
  bool _makeLists = false;
  String? _statusMessage;
  String? _selectedFilePath;
  String? _outputFolderPath;

  @override
  void initState() {
    super.initState();
    _loadSavedPath();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates({bool manual = false}) async {
    final updateInfo = await UpdateService().checkForUpdate();
    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => UpdateDialog(
          version: updateInfo['version'],
          description: updateInfo['body'],
          apkUrl: updateInfo['apkUrl'],
        ),
      );
    } else if (manual && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No updates available')));
    }
  }

  Future<void> _loadSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('saved_output_path');
    if (savedPath != null) {
      if (mounted) {
        setState(() {
          _outputFolderPath = savedPath;
        });
      }
    }
  }

  // ... (rest of the file methods like _pickFile, _pickOutputFolder, _generatePack)

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mcstructure'],
    );

    if (result != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _fileController.text = result.files.single.name;
        if (_nameController.text.isEmpty) {
          _nameController.text = result.files.single.name.replaceAll(
            ".mcstructure",
            "",
          );
        }
      });
    }
  }

  Future<void> _pickOutputFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      setState(() {
        _outputFolderPath = path;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_output_path', path);
    }
  }

  Future<void> _generatePack() async {
    if (_selectedFilePath == null || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file and enter a pack name'),
        ),
      );
      return;
    }

    // Request permissions especially in Android 11+
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = "Initializing...";
    });

    try {
      final core = StructuraCore(_nameController.text);

      setState(() => _statusMessage = "Loading Assets...");
      await core.init();

      core.setOpacity(_opacity);
      core.addModel(_nameController.text, _selectedFilePath!);

      setState(
        () =>
            _statusMessage = "Processing Structure (this may take a while)...",
      );
      // Give UI a moment to update
      await Future.delayed(const Duration(milliseconds: 100));

      String summary = await core.generateWithNametags();

      setState(() => _statusMessage = "$summary\nCompiling Pack...");
      String packPath = await core.compilePack(makeLists: _makeLists);

      setState(() {
        _statusMessage = "Pack generated!";
        _isGenerating = false;
      });

      String targetPath;

      if (_outputFolderPath != null) {
        // Auto-save to selected folder
        final fileName = '${_nameController.text}.mcpack';
        targetPath = '$_outputFolderPath/$fileName';
        await File(packPath).copy(targetPath);

        // Copy material list if it exists
        if (_makeLists) {
          final materialListPath =
              '${packPath.replaceAll('.mcpack', '')}_materials.txt';
          final materialListFile = File(materialListPath);
          if (await materialListFile.exists()) {
            final materialListTarget =
                '$_outputFolderPath/${_nameController.text}_materials.txt';
            await materialListFile.copy(materialListTarget);
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $targetPath')));
      } else {
        // Prompt to save
        setState(() {
          _statusMessage = "Prompting to save...";
        });

        final File packFile = File(packPath);
        final Uint8List packBytes = await packFile.readAsBytes();

        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Resource Pack',
          fileName: '${_nameController.text}.mcpack',
          bytes: packBytes,
        );

        // Save material list to same location when it is toggled on
        if (outputFile != null && mounted) {
          if (_makeLists) {
            final materialListPath =
                '${packPath.replaceAll('.mcpack', '')}_materials.txt';
            final materialListFile = File(materialListPath);
            if (await materialListFile.exists()) {
              final materialListBytes = await materialListFile.readAsBytes();
              final materialListOutput = outputFile.replaceAll(
                '.mcpack',
                '_materials.txt',
              );
              await File(materialListOutput).writeAsBytes(materialListBytes);
            }
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Saved to $outputFile')));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save cancelled. File is at $packPath')),
          );
        }
      }
    } catch (e, stack) {
      print(e);
      print(stack);
      setState(() {
        _statusMessage = "Error: $e";
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Structura Mobile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.update),
            tooltip: 'Check for Updates',
            onPressed: () => _checkForUpdates(manual: true),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Structure File (.mcstructure)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fileController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: "No file selected",
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _pickFile,
                          child: const Text("Browse"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Configuration",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(
                              text: _outputFolderPath ?? "Ask every time",
                            ),
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: "Save Folder",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.folder),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _pickOutputFolder,
                          child: const Text("Set"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "Pack Name",
                        border: OutlineInputBorder(),
                        helperText: "Unique name for your resource pack",
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text("Transparency / Opacity"),
                    Slider(
                      value: _opacity,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      label: _opacity.toStringAsFixed(1),
                      onChanged: (v) => setState(() => _opacity = v),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      title: const Text("Make Lists"),
                      subtitle: const Text("Export material list as .txt file"),
                      value: _makeLists,
                      onChanged: (bool? value) {
                        setState(() => _makeLists = value ?? false);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            if (_isGenerating)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage ?? "Working...",
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: _generatePack,
                icon: const Icon(Icons.build),
                label: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("GENERATE PACK", style: TextStyle(fontSize: 18)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
              ),

            if (!_isGenerating && _statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusMessage!.startsWith("Error")
                        ? Colors.red
                        : Colors.green[800],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
