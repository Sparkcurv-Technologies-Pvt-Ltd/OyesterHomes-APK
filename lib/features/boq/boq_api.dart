import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';

/// An API error whose `detail` was an object (`{message, errors}` from the BOQ import, `{message, id}` when a
/// sample BOQ is already in the library). The web's BOQ `errText` shows `detail.message`, and the import
/// dialog lists `detail.errors`; ApiClient turns object details into raw map text, so BOQ calls that can
/// return one go through [boqSend] instead.
class BoqApiException extends ApiException {
  final List<dynamic> errors;
  BoqApiException(super.message, {super.statusCode, this.errors = const []});
}

String _detailText(dynamic d) {
  if (d is String) return d;
  if (d is List) return d.map((e) => e is Map ? (e['msg'] ?? e.toString()) : e.toString()).join(' ');
  if (d is Map && d['message'] != null) return d['message'].toString();
  if (d is Map && d['msg'] is String) return d['msg'] as String;
  return d?.toString() ?? 'Something went wrong';
}

/// Same request as ApiClient (base URL, Bearer token, 401 hook come from its Dio interceptors), with the
/// BOQ router's object-shaped error details read the way the web reads them.
Future<dynamic> boqSend(ApiClient api, String method, String path, {dynamic data}) async {
  try {
    final res = await api.dio.request<dynamic>(path, data: data, options: Options(method: method));
    return res.data;
  } on DioException catch (e) {
    final r = e.response;
    if (r == null) throw ApiException('Could not reach the server. Check your connection.');
    final body = r.data;
    final d = body is Map ? body['detail'] : null;
    if (d == null) throw ApiException('Something went wrong. Please try again.', statusCode: r.statusCode);
    final errors = d is Map && d['errors'] is List ? d['errors'] as List : const [];
    throw BoqApiException(_detailText(d), statusCode: r.statusCode, errors: errors);
  }
}

/// Multipart POST (Excel import) through [boqSend].
Future<dynamic> boqUpload(ApiClient api, String path, String filePath, String fileName, Map<String, dynamic> fields) async {
  final form = FormData.fromMap({...fields, 'file': await MultipartFile.fromFile(filePath, filename: fileName)});
  return boqSend(api, 'POST', path, data: form);
}

/// Endpoints for a project's BOQ and a library template (the two APIs return the same shape).
class BoqEndpoints {
  final bool isProject;
  final int id;
  const BoqEndpoints(this.isProject, this.id);

  String get get => isProject ? '/projects/$id/boq' : '/boq-templates/$id';
  String get add => isProject ? '/projects/$id/boq/items' : '/boq-templates/$id/items';
  String item(dynamic i) => isProject ? '/boq/items/$i' : '/boq-template-items/$i';
  String get import => isProject ? '/projects/$id/boq/import' : '/boq-templates/$id/import';
  String get export => isProject ? '/projects/$id/boq/export' : '/boq-templates/$id/export';
  String get pdf => '/projects/$id/boq/pdf';
}
