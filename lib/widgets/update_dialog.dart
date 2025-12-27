import 'package:flutter/material.dart';
import '../core/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final String version;
  final String description;
  final String apkUrl;

  const UpdateDialog({
    super.key,
    required this.version,
    required this.description,
    required this.apkUrl,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _downloadProgress;
  String? _errorMessage;
  bool _isDownloading = false;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _downloadProgress = 0;
    });

    await UpdateService().downloadAndInstall(
      widget.apkUrl,
      (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _errorMessage = error;
            _isDownloading = false;
            _downloadProgress = null;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update Available: ${widget.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isDownloading && _errorMessage == null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(child: Text(widget.description)),
            ),
          if (_isDownloading) ...[
            const Text('Downloading...'),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _downloadProgress),
            const SizedBox(height: 5),
            Text(
              '${((_downloadProgress ?? 0) * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_errorMessage != null)
            Text(
              'Error: $_errorMessage',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _startDownload,
            child: const Text('Update'),
          ),
      ],
    );
  }
}
