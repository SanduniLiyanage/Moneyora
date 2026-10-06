/// The only networked code in the application (NFR-MNT-006).
///
/// Everything here throws [AppException] on failure, per the layer contract in
/// `docs/ARCHITECTURE.md` §3; `LlmRepositoryImpl` converts.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/agent_tool.dart';
import '../../domain/entities/llm_step.dart';
import '../../domain/entities/tool_exchange.dart';
import '../models/llm_dtos.dart';

/// Supplies the key for the reasoning model.
///
/// An interface for the same reason [EncryptionKeyStore] is one: the real
/// implementation talks to the platform keychain over a channel that cannot
/// run in a unit test.
abstract class LlmApiKeyStore {
  /// Returns the stored key, or null when the user has not set one.
  Future<String?> read();

  /// Stores [key], replacing any existing one.
  Future<void> write(String key);

  /// Removes the stored key.
  Future<void> clear();
}

/// Asks Gemini what to do next.
///
/// ## What this class is careful about
///
/// * **The key is read per call and never held.** A field would keep it in
///   memory for the life of the app, and in a heap dump for longer.
/// * **The key travels in a header, not the query string.** URLs are logged by
///   proxies, crash reporters and `flutter run` itself; headers are not.
/// * **Nothing is logged.** Not the request, not the response, not the key.
///   The request carries the user's question and their spending; a debug print
///   left in would put both in logcat.
class GeminiRemoteDataSource {
  /// Creates a datasource over [client], reading its key from [keyStore].
  GeminiRemoteDataSource(
    this._client,
    this._keyStore, {
    this.model = defaultModel,
    this.fallback = fallbackModel,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final http.Client _client;
  final LlmApiKeyStore _keyStore;

  /// The model to reason with.
  ///
  /// Configurable rather than fixed: model names are retired on a schedule
  /// that has nothing to do with this repository, and a hard-coded one turns
  /// into a feature that stops working for no visible reason.
  final String model;

  /// How long to wait before giving up.
  ///
  /// Under NFR-PER-001's six seconds for a typical query, this looks generous;
  /// it is a ceiling for the worst case, not a target. A request still running
  /// after twenty seconds will not produce a useful answer, and the user is
  /// looking at a spinner the whole time.
  final Duration timeout;

  /// What [model] falls back to when Google answers that it does not exist.
  final String fallback;

  /// The current Flash model, by Google's alias for it, which moves to each
  /// new Flash release.
  ///
  /// 1.0.0 and 1.0.1 asked for `gemini-2.0-flash` by name. Google shut it down
  /// on 2026-06-01, and every question failed with "could not answer that",
  /// on an app that cannot update itself.
  static const String defaultModel = 'gemini-flash-latest';

  /// A dated stable model on the free tier, asked only if [defaultModel]
  /// is ever withdrawn.
  static const String fallbackModel = 'gemini-3.5-flash';

  static const String _host = 'generativelanguage.googleapis.com';

  /// Sends one turn and returns what the model decided.
  Future<LlmStep> reason({
    required String question,
    required List<AgentTool> tools,
    required List<ToolExchange> history,
  }) async {
    final apiKey = await _keyStore.read();
    if (apiKey == null || apiKey.isEmpty) {
      throw const ServerException(
        'Ask Moneyora has no API key yet. Add one on the Ask Moneyora screen.',
      );
    }

    final body = jsonEncode(
      GeminiDtos.buildRequestBody(
        question: question,
        tools: tools,
        history: history,
        today: _clock(),
      ),
    );

    var response = await _post(model, apiKey, body);
    // 404 is a model Google no longer serves, not a question it could not
    // answer: the one status worth a second request.
    if (response.statusCode == 404 && fallback != model) {
      response = await _post(fallback, apiKey, body);
    }

    if (response.statusCode != 200) throw _statusException(response);

    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('The reply was not an object.');
      }
      decoded = parsed;
    } on FormatException catch (e) {
      throw ServerException('The assistant replied with nonsense.', cause: e);
    }

    try {
      return GeminiDtos.parseResponse(decoded);
    } on FormatException catch (e) {
      throw ServerException(
        'The assistant replied with something unexpected.',
        cause: e,
      );
    }
  }

  Future<http.Response> _post(String model, String apiKey, String body) async {
    final uri = Uri.https(_host, '/v1beta/models/$model:generateContent');
    try {
      return await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              // Not `?key=` — a URL is logged in places a header is not.
              'x-goog-api-key': apiKey,
            },
            body: body,
          )
          .timeout(timeout);
    } on Exception catch (e) {
      // Any transport problem: no route, DNS, TLS, timeout. The message says
      // nothing about the cause because none of it helps the reader.
      throw ServerException('Could not reach the assistant.', cause: e);
    }
  }

  /// Maps a failed reply onto a message, keeping the code for the repository.
  ///
  /// 429 is the one worth separating by status: it is the free tier's daily
  /// limit, it resolves by waiting, and telling the user to "try again" now
  /// would be advice that cannot work. A mistyped key arrives as a 400 whose
  /// body names `API_KEY_INVALID`, not as a 401, so the body is read for it.
  static ServerException _statusException(http.Response response) {
    final status = response.statusCode;
    if (status == 401 ||
        status == 403 ||
        response.body.contains('API_KEY_INVALID')) {
      return ServerException(
        'Google did not accept the API key. Check it, or enter it again with '
        'Change API key.',
        statusCode: status,
      );
    }
    return switch (status) {
      429 => ServerException(
        'The assistant has used up its quota for now. Try again later.',
        statusCode: status,
      ),
      404 => ServerException(
        'The assistant is not available to this version of Moneyora. '
        'Update the app.',
        statusCode: status,
      ),
      >= 500 => ServerException(
        'The assistant is having trouble. Try again shortly.',
        statusCode: status,
      ),
      _ => ServerException(
        'The assistant could not answer that ($status).',
        statusCode: status,
      ),
    };
  }
}
