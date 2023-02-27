part of '_internal.dart';

/// {@template response}
/// An HTTP response.
/// {@endtemplate}
class Response {
  /// Create a [Response] with a string body.
  Response({
    int statusCode = 200,
    String? body,
    Map<String, Object>? headers,
    Encoding? encoding,
  }) : this._(
          shelf.Response(
            statusCode,
            body: body,
            headers: headers,
            encoding: encoding,
          ),
        );

  /// Create a [Response] with a byte array body.
  Response.bytes({
    int statusCode = 200,
    List<int>? body,
    Map<String, Object>? headers,
  }) : this._(
          shelf.Response(
            statusCode,
            body: body,
            headers: headers,
          ),
        );

  /// Create a [Response] with a json encoded body.
  Response.json({
    int statusCode = 200,
    Object? body = const <String, dynamic>{},
    Map<String, Object> headers = const <String, Object>{},
  }) : this(
          statusCode: statusCode,
          body: body != null ? jsonEncode(body) : null,
          headers: {
            ...headers,
            HttpHeaders.contentTypeHeader: ContentType.json.value,
          },
        );

  /// Create a [Response] with a json encoded body.
  Response.file({
    required File body,
    Map<String, Object> headers = const <String, Object>{},
    HttpMethod method = HttpMethod.get,
    String? rangeHeader,
  }) {
    _response = _fileRangeResponse(method, body, rangeHeader, headers);
  }

  Response._(this._response);

  late shelf.Response _response;

  /// The HTTP status code of the response.
  int get statusCode => _response.statusCode;

  /// The HTTP headers with case-insensitive keys.
  /// The returned map is unmodifiable.
  Map<String, String> get headers => _response.headers;

  /// Returns a [Stream] representing the body.
  Stream<List<int>> bytes() => _response.read();

  /// Returns a [Future] containing the body as a [String].
  Future<String> body() async {
    const responseBodyKey = 'dart_frog.response.body';
    final bodyFromContext =
        _response.context[responseBodyKey] as Completer<String>?;
    if (bodyFromContext != null) return bodyFromContext.future;

    final completer = Completer<String>();
    try {
      _response = _response.change(
        context: {..._response.context, responseBodyKey: completer},
      );
      completer.complete(await _response.readAsString());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }

    return completer.future;
  }

  /// Returns a [Future] containing the form data as a [Map].
  Future<Map<String, String>> formData() {
    return parseFormData(headers: headers, body: body);
  }

  /// Returns a [Future] containing the body text parsed as a json object.
  /// This object could be anything that can be represented by json
  /// e.g. a map, a list, a string, a number, a bool...
  Future<dynamic> json() async => jsonDecode(await body());

  /// Creates a new [Response] by copying existing values and applying specified
  /// changes.
  Response copyWith({Map<String, Object?>? headers, Object? body}) {
    return Response._(_response.change(headers: headers, body: body));
  }

  shelf.Response _fileRangeResponse(
    HttpMethod method,
    File file,
    String? range,
    Map<String, Object> headers,
  ) {
    if (range == null || !file.existsSync()) {
      return shelf.Response(HttpStatus.badRequest);
    }

    final matches = RegExp(r'^bytes=(\d*)\-(\d*)$').firstMatch(range);
    // Ignore ranges other than bytes
    if (matches == null) {
      return shelf.Response(HttpStatus.badRequest);
    }

    final actualLength = file.lengthSync();
    final startMatch = matches[1]!;
    final endMatch = matches[2]!;
    if (startMatch.isEmpty && endMatch.isEmpty) {
      return shelf.Response(HttpStatus.badRequest);
    }

    int start; // First byte position - inclusive.
    int end; // Last byte position - inclusive.
    if (startMatch.isEmpty) {
      start = actualLength - int.parse(endMatch);
      if (start < 0) start = 0;
      end = actualLength - 1;
    } else {
      start = int.parse(startMatch);
      end = endMatch.isEmpty ? actualLength - 1 : int.parse(endMatch);
    }

    // If the range is syntactically invalid the Range header
    // MUST be ignored (RFC 2616 section 14.35.1).
    if (start > end) return shelf.Response(HttpStatus.badRequest);

    if (end >= actualLength) {
      end = actualLength - 1;
    }
    if (start >= actualLength) {
      return shelf.Response(
        HttpStatus.requestedRangeNotSatisfiable,
        headers: headers,
      );
    }
    return shelf.Response(
      HttpStatus.partialContent,
      body: method == HttpMethod.head ? null : file.openRead(start, end + 1),
      headers: {
        ...headers,
        HttpHeaders.contentLengthHeader: (end - start + 1).toString(),
        HttpHeaders.contentRangeHeader: 'bytes $start-$end/$actualLength',
      },
    );
  }
}
