import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Global bridge to allow static services to update Riverpod state
class GlobalProviderContainer {
  static ProviderContainer? _container;

  static void initialize(ProviderContainer container) {
    _container = container;
  }

  static ProviderContainer? get maybeInstance => _container;

  static ProviderContainer get instance {
    if (_container == null) {
      // Fallback for extreme race conditions on Web
      return ProviderContainer();
    }
    return _container!;
  }
}
