// lib/network/network_monitor.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkType { none, wifi, lte, other }

NetworkType toNetworkType(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi)) return NetworkType.wifi;
  if (results.contains(ConnectivityResult.mobile)) return NetworkType.lte;
  if (results.contains(ConnectivityResult.none)) return NetworkType.none;
  return NetworkType.other;
}

final networkMonitorProvider = StreamProvider<NetworkType>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map(toNetworkType);
});

final currentNetworkProvider = FutureProvider<NetworkType>((ref) async {
  final results = await Connectivity().checkConnectivity();
  return toNetworkType(results);
});
