import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final isOnlineProvider = StateNotifierProvider<ConnectivityNotifier, bool>((ref) {
  return ConnectivityNotifier();
});

class ConnectivityNotifier extends StateNotifier<bool> {
  Timer? _timer;

  ConnectivityNotifier() : super(true) {
    checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => checkConnection());
  }

  Future<void> checkConnection() async {
    try {
      final result = await InternetAddress.lookup('mangalib.org').timeout(const Duration(seconds: 4));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (state != online) {
        state = online;
      }
    } catch (_) {
      if (state != false) {
        state = false;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
