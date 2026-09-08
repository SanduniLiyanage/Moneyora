/// The Copilot's layer boundary. Exceptions become failures here and nowhere
/// else, exactly as every other repository in the app does it.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/agent_tool.dart';
import '../../domain/entities/llm_step.dart';
import '../../domain/entities/tool_exchange.dart';
import '../../domain/repositories/llm_repository.dart';
import '../datasources/gemini_remote_datasource.dart';

/// Fulfils [LlmRepository] against Gemini.
///
/// The domain names no vendor, so swapping providers is a second datasource
/// and a different binding in `injection.dart`. The loop, the tools and this
/// contract do not change (NFR-POR-007).
class LlmRepositoryImpl implements LlmRepository {
  /// Creates a repository over [_remote].
  const LlmRepositoryImpl(this._remote);

  final GeminiRemoteDataSource _remote;

  @override
  Future<Either<Failure, LlmStep>> reason({
    required String question,
    required List<AgentTool> tools,
    required List<ToolExchange> history,
  }) async {
    try {
      return Right(
        await _remote.reason(
          question: question,
          tools: tools,
          history: history,
        ),
      );
    } on AppException catch (e) {
      return Left(_toFailure(e));
    }
  }

  /// A spent quota is told apart from every other server error, because it is
  /// the only one where "try again in a minute" is wrong advice and "try again
  /// tomorrow" is right (FR-COP-015).
  static Failure _toFailure(AppException e) => switch (e) {
    ServerException(statusCode: 429) => QuotaFailure(e.message),
    ServerException() => ServerFailure(e.message),
    NetworkException() => const NetworkFailure(),
    CacheException() => CacheFailure(e.message),
    EncryptionException() => EncryptionFailure(e.message),
    OcrException() => OcrFailure(e.message),
    PermissionException() => PermissionFailure(e.message),
  };
}
