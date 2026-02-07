import 'package:flutter/foundation.dart';

/// サービスエラーの種類
enum ServiceErrorType {
  network,
  notFound,
  unauthorized,
  serverError,
  unknown,
}

/// サービス例外
/// サービス層で発生するエラーを統一的に扱うための例外クラス
class ServiceException implements Exception {
  final String message;
  final ServiceErrorType type;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const ServiceException({
    required this.message,
    this.type = ServiceErrorType.unknown,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'ServiceException: $message (type: $type)';

  /// ネットワークエラーかどうか
  bool get isNetworkError => type == ServiceErrorType.network;

  /// 再試行可能なエラーかどうか
  bool get isRetryable =>
      type == ServiceErrorType.network || type == ServiceErrorType.serverError;
}

/// ベースサービスクラス
/// すべてのサービスクラスの基底クラスとして使用
/// 共通のロギング、エラーハンドリング機能を提供
abstract class BaseService {
  /// サービス名（ログ出力用）
  String get serviceName => runtimeType.toString();

  /// デバッグログを出力
  @protected
  void logDebug(String message) {
    if (kDebugMode) {
      print('[$serviceName] $message');
    }
  }

  /// 情報ログを出力
  @protected
  void logInfo(String message) {
    if (kDebugMode) {
      print('ℹ️ [$serviceName] $message');
    }
  }

  /// 警告ログを出力
  @protected
  void logWarning(String message) {
    if (kDebugMode) {
      print('⚠️ [$serviceName] $message');
    }
  }

  /// エラーログを出力
  @protected
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      print('❌ [$serviceName] $message');
      if (error != null) {
        print('  Error: $error');
      }
      if (stackTrace != null) {
        print('  StackTrace: $stackTrace');
      }
    }
  }

  /// 成功ログを出力
  @protected
  void logSuccess(String message) {
    if (kDebugMode) {
      print('✅ [$serviceName] $message');
    }
  }

  /// 安全に非同期処理を実行（エラーをキャッチしてログ出力）
  @protected
  Future<T?> safeExecute<T>(
    Future<T> Function() action, {
    String? operationName,
    T? defaultValue,
    bool rethrowError = false,
  }) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      logError(
        operationName != null ? '$operationName failed' : 'Operation failed',
        e,
        stackTrace,
      );
      if (rethrowError) {
        rethrow;
      }
      return defaultValue;
    }
  }

  /// 安全にリストを取得（エラー時は空リストを返す）
  @protected
  Future<List<T>> safeGetList<T>(
    Future<List<T>> Function() action, {
    String? operationName,
  }) async {
    return await safeExecute<List<T>>(
          action,
          operationName: operationName,
          defaultValue: <T>[],
        ) ??
        <T>[];
  }

  /// エラーをServiceExceptionに変換
  @protected
  ServiceException wrapError(
    Object error,
    String message, {
    StackTrace? stackTrace,
  }) {
    ServiceErrorType type = ServiceErrorType.unknown;

    // エラータイプを判定
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection')) {
      type = ServiceErrorType.network;
    } else if (errorString.contains('not found') ||
        errorString.contains('404')) {
      type = ServiceErrorType.notFound;
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401') ||
        errorString.contains('permission')) {
      type = ServiceErrorType.unauthorized;
    } else if (errorString.contains('500') ||
        errorString.contains('server error')) {
      type = ServiceErrorType.serverError;
    }

    return ServiceException(
      message: message,
      type: type,
      originalError: error,
      stackTrace: stackTrace,
    );
  }
}

/// シングルトンサービスのミックスイン
/// サービスをシングルトンパターンで実装するためのヘルパー
mixin SingletonService<T extends BaseService> {
  static final Map<Type, BaseService> _instances = {};

  /// シングルトンインスタンスを取得または作成
  static T getInstance<T extends BaseService>(T Function() factory) {
    final type = T;
    if (!_instances.containsKey(type)) {
      _instances[type] = factory();
    }
    return _instances[type] as T;
  }

  /// インスタンスをリセット（テスト用）
  static void resetInstance<T extends BaseService>() {
    _instances.remove(T);
  }

  /// すべてのインスタンスをリセット（テスト用）
  static void resetAllInstances() {
    _instances.clear();
  }
}
