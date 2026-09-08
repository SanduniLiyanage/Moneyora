import 'package:connectivity_plus/connectivity_plus.dart';

import 'network_info.dart';

/// [NetworkInfo] over `connectivity_plus`.
///
/// Reports what the platform says about the radio, which is the most any
/// device can know without sending a packet: a phone joined to a captive
/// portal reports a connection it does not have. That is why this answers
/// "worth trying" rather than "will succeed", and why every caller still
/// handles failure afterwards.
class ConnectivityNetworkInfo implements NetworkInfo {
  /// Creates a check over [connectivity], defaulting to the platform's.
  ConnectivityNetworkInfo({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isConnected async {
    // A device can hold several interfaces at once — wifi and mobile during a
    // handover — so the answer is a list, and any live one will do.
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }
}
