import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../network/api_client.dart';
import '../storage/api_config.dart';
import '../widgets/common.dart';

/// A file the user picked, before upload.
class PickedFile {
  final String path;
  final String name;
  final int size;
  const PickedFile(this.path, this.name, this.size);
}

/// Asks Camera / Gallery / Files (or only Files when [imagesOnly] is false and [allowCamera] is false),
/// then returns the picked file. Null when cancelled.
Future<PickedFile?> pickFile(BuildContext context,
    {bool allowCamera = true, bool imagesOnly = false, List<String>? extensions}) async {
  String? source = 'files';
  if (allowCamera) {
    source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, 'gallery')),
          if (!imagesOnly)
            ListTile(leading: const Icon(Icons.attach_file), title: const Text('Choose a file'), onTap: () => Navigator.pop(ctx, 'files')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return null;
  }
  if (source == 'camera' || source == 'gallery') {
    final x = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 80, maxWidth: 2200);
    if (x == null) return null;
    return PickedFile(x.path, x.name, await File(x.path).length());
  }
  final res = await FilePicker.pickFiles(
    type: imagesOnly ? FileType.image : (extensions == null ? FileType.any : FileType.custom),
    allowedExtensions: imagesOnly ? null : extensions,
  );
  final f = res?.files.single;
  if (f == null || f.path == null) return null;
  return PickedFile(f.path!, f.name, f.size);
}

/// Picks a file and uploads it to POST /upload. Returns `{url, filename}` or null when cancelled.
/// Shows a toast on failure (e.g. "File type .xyz not allowed", "File too large (max 10MB)").
Future<Map<String, dynamic>?> pickAndUpload(BuildContext context, ApiClient api,
    {bool allowCamera = true, bool imagesOnly = false, List<String>? extensions}) async {
  final f = await pickFile(context, allowCamera: allowCamera, imagesOnly: imagesOnly, extensions: extensions);
  if (f == null) return null;
  if (f.size > 10 * 1024 * 1024) {
    if (context.mounted) showToast(context, 'File too large (max 10MB)', error: true);
    return null;
  }
  try {
    return await api.upload(f.path, filename: f.name);
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
    return null;
  }
}

/// Opens a stored file (`/api/uploads/...` or a full URL): downloads it with auth, then hands it
/// to whatever app opens that type. Falls back to the browser.
Future<void> openServerFile(BuildContext context, ApiClient api, String url, {String? name}) async {
  try {
    final full = ApiConfig.fileUrl(url);
    final rel = full.startsWith('${ApiConfig.baseUrlSync}/api') ? full.substring('${ApiConfig.baseUrlSync}/api'.length) : null;
    if (rel == null) {
      await launchUrl(Uri.parse(full), mode: LaunchMode.externalApplication);
      return;
    }
    final (bytes, _) = await api.download(rel);
    final fname = name ?? Uri.parse(full).pathSegments.last;
    final file = await _saveTemp(fname, bytes);
    final r = await OpenFilex.open(file.path);
    if (r.type != ResultType.done) await launchUrl(Uri.parse(full), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
  }
}

/// Downloads an export / print endpoint (PDF, Excel, HTML) and opens it. [path] is relative to /api.
Future<void> downloadAndOpen(BuildContext context, ApiClient api, String path,
    {required String fallbackName, Map<String, dynamic>? params}) async {
  try {
    final (bytes, disposition) = await api.download(path, params: params);
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition ?? '');
    final file = await _saveTemp(match?.group(1) ?? fallbackName, bytes);
    final r = await OpenFilex.open(file.path);
    if (r.type != ResultType.done && context.mounted) {
      showToast(context, r.message.isEmpty ? 'No app on this phone can open ${file.uri.pathSegments.last}' : r.message, error: true);
    }
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
  }
}

/// Downloads an export and opens the Android share sheet for it (WhatsApp, email, Drive...).
Future<void> downloadAndShare(BuildContext context, ApiClient api, String path,
    {required String fallbackName, Map<String, dynamic>? params, String? text}) async {
  try {
    final (bytes, disposition) = await api.download(path, params: params);
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition ?? '');
    final file = await _saveTemp(match?.group(1) ?? fallbackName, bytes);
    await Share.shareXFiles([XFile(file.path)], text: text);
  } catch (e) {
    if (context.mounted) showToast(context, errorText(e), error: true);
  }
}

/// Saves bytes you already have (e.g. generated HTML) and opens them.
Future<void> openBytes(BuildContext context, List<int> bytes, String name) async {
  final file = await _saveTemp(name, bytes);
  final r = await OpenFilex.open(file.path);
  if (r.type != ResultType.done && context.mounted) showToast(context, 'No app on this phone can open $name', error: true);
}

Future<void> shareText(String text, {String? subject}) => Share.share(text, subject: subject);

/// tel:, mailto:, https:, whatsapp links.
Future<void> openExternal(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showToast(context, 'No app can open this link', error: true);
}

Future<File> _saveTemp(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
