import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final Dio _dio = Dio();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/joncarl-15/structura-mobile/releases/latest',
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data;
        final String tagName = data['tag_name'];
        final String body = data['body'] ?? '';
        final List assets = data['assets'];
        final String? apkUrl = assets.firstWhere(
          (asset) => asset['name'].toString().endsWith('.apk'),
          orElse: () => null,
        )?['browser_download_url'];

        if (apkUrl == null) return null;

        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        String currentVersion = packageInfo.version;

        // Simple version comparison (assumes format 1.0.0 etc)
        // You might need more robust comparison if tags are complex
        if (_isNewer(tagName, currentVersion)) {
          return {'version': tagName, 'body': body, 'apkUrl': apkUrl};
        }
      }
    } catch (e) {
      print('Error checking for update: $e');
    }
    return null;
  }

  bool _isNewer(String newVersion, String currentVersion) {
    // Remove 'v' prefix if present
    newVersion = newVersion.replaceAll('v', '');
    currentVersion = currentVersion.replaceAll('v', '');

    if (newVersion == currentVersion) {
      print(
        "Update check: You are on the latest version ($newVersion). No update needed.",
      );
      return false;
    }

    print("Checking update: Remote($newVersion) vs Local($currentVersion)");

    List<String> newParts = newVersion.split('.');
    List<String> currentParts = currentVersion.split('.');

    for (int i = 0; i < newParts.length && i < currentParts.length; i++) {
      int newPart = int.tryParse(newParts[i]) ?? 0;
      int currentPart = int.tryParse(currentParts[i]) ?? 0;
      if (newPart > currentPart) return true;
      if (newPart < currentPart) return false;
    }
    // If we are here, they are equal so far.
    // If new version has more parts (e.g. 1.0.1 vs 1.0), it's newer
    return newParts.length > currentParts.length;
  }

  Future<void> downloadAndInstall(
    String url,
    Function(double) onProgress,
    Function(String?) onError,
  ) async {
    // Request permission if needed (Android 13+ need notification permission,
    // install packages permission is requested at runtime by OS usually for APKs)

    // For install packages, we don't ask it here, the intent does it.
    // We might need storage permission if saving to external, but we'll use app support dir.

    if (Platform.isAndroid) {
      // Android 13+ notification permission
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    try {
      Directory dir = await getApplicationDocumentsDirectory();
      String savePath = '${dir.path}/update.apk';

      // Delete old file if exists
      File file = File(savePath);
      if (file.existsSync()) {
        file.deleteSync();
      }

      await _showProgressNotification(0);

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            double progress = received / total;
            onProgress(progress);
            _showProgressNotification((progress * 100).toInt());
          }
        },
      );

      await _cancelNotification();
      // Install
      print("Download complete. Attempting to open: $savePath");
      final result = await OpenFile.open(
        savePath,
        type: "application/vnd.android.package-archive",
      );
      print("Open result: ${result.type} | Message: ${result.message}");

      if (result.type != ResultType.done) {
        onError("Installation failed: ${result.message}");
      }
    } catch (e) {
      await _cancelNotification();
      onError(e.toString());
    }
  }

  Future<void> _showProgressNotification(int progress) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'update_channel',
          'App Updates',
          channelDescription: 'Notifications for app updates',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: progress,
        );
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await _notificationsPlugin.show(
      888,
      'Downloading Update',
      '$progress%',
      platformChannelSpecifics,
    );
  }

  Future<void> _cancelNotification() async {
    await _notificationsPlugin.cancel(888);
  }
}
