import 'dart:convert';
import 'package:dio/dio.dart';
import '../storage/api_config.dart';
import '../storage/token_storage.dart';

/// Any non-2xx response, with the backend's `detail` already turned into readable text.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Same rules as the web's `formatApiErrorDetail`: string detail, list of {msg}, or {msg}.
String _extractDetail(dynamic data) {
  var body = data;
  if (body is List<int>) {
    try {
      body = jsonDecode(utf8.decode(body));
    } catch (_) {
      body = null;
    }
  }
  if (body is Map && body['detail'] != null) {
    final d = body['detail'];
    if (d is String) return d;
    if (d is List) return d.map((e) => e is Map ? (e['msg'] ?? e.toString()) : e.toString()).join(' ');
    if (d is Map && d['msg'] is String) return d['msg'];
    if (d is Map && d['message'] is String) return d['message'];
    return d.toString();
  }
  return 'Something went wrong. Please try again.';
}

/// Dio configured like the web's axios instance: base `${ApiConfig}/api`, a Bearer token
/// (the backend accepts it as a fallback to its cookie), and a 401 hook that signs the user out.
///
/// Every method returns the decoded JSON body (`res.data` on the web).
class ApiClient {
  late final Dio dio;
  final TokenStorage tokenStorage;
  void Function()? onUnauthorized;

  ApiClient(this.tokenStorage) {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      contentType: 'application/json',
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final base = await ApiConfig.getBaseUrl();
        options.baseUrl = '$base/api';
        final token = await tokenStorage.read();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) {
        final path = error.requestOptions.path;
        if (error.response?.statusCode == 401 && !path.startsWith('/auth/login')) onUnauthorized?.call();
        handler.next(error);
      },
    ));
  }

  /// Query values that are null or empty strings are dropped, as axios drops undefined.
  Map<String, dynamic>? _clean(Map<String, dynamic>? p) =>
      p == null ? null : (Map.of(p)..removeWhere((_, v) => v == null || (v is String && v.isEmpty)));

  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async =>
      (await _guard(() => dio.get(path, queryParameters: _clean(params)))).data;

  Future<dynamic> post(String path, {dynamic data, Map<String, dynamic>? params}) async =>
      (await _guard(() => dio.post(path, data: data, queryParameters: _clean(params)))).data;

  Future<dynamic> put(String path, {dynamic data, Map<String, dynamic>? params}) async =>
      (await _guard(() => dio.put(path, data: data, queryParameters: _clean(params)))).data;

  Future<dynamic> patch(String path, {dynamic data, Map<String, dynamic>? params}) async =>
      (await _guard(() => dio.patch(path, data: data, queryParameters: _clean(params)))).data;

  Future<dynamic> delete(String path, {dynamic data, Map<String, dynamic>? params}) async =>
      (await _guard(() => dio.delete(path, data: data, queryParameters: _clean(params)))).data;

  /// POST /upload (multipart, 10MB max on the server). Returns `{url, filename}`.
  Future<Map<String, dynamic>> upload(String filePath, {String? filename}) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath, filename: filename)});
    final res = await _guard(() => dio.post('/upload', data: form));
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Multipart POST for endpoints that take files plus form fields (values may be MultipartFile).
  Future<dynamic> postMultipart(String path, Map<String, dynamic> fields, {Map<String, dynamic>? params}) async {
    final res = await _guard(() => dio.post(path, data: FormData.fromMap(fields), queryParameters: _clean(params)));
    return res.data;
  }

  /// Binary GET (PDF / Excel / printable exports). Returns the bytes and the Content-Disposition header.
  Future<(List<int>, String?)> download(String path, {Map<String, dynamic>? params}) async {
    final res = await _guard(() => dio.get<List<int>>(path,
        queryParameters: _clean(params), options: Options(responseType: ResponseType.bytes)));
    return (res.data ?? const <int>[], res.headers.value('content-disposition'));
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.response != null) {
        throw ApiException(_extractDetail(e.response!.data), statusCode: e.response!.statusCode);
      }
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }
}
