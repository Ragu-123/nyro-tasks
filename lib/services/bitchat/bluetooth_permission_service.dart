import 'package:flutter/services.dart';

class BluetoothPermissionService {
  static const MethodChannel _channel = MethodChannel('io.github.thelazyindian.tasks/bluetooth_permissions');
  static const MethodChannel _fallbackChannel = MethodChannel('io.github.thelazyindian.tasks/native');

  static Future<bool> checkPermissions() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkBluetoothPermissions');
      if (granted != null) return granted;
    } catch (_) {}

    try {
      final bool? granted = await _fallbackChannel.invokeMethod<bool>('checkBluetoothPermissions');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> requestPermissions() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>('requestBluetoothPermissions');
      if (granted != null) return granted;
    } catch (_) {}

    try {
      final bool? granted = await _fallbackChannel.invokeMethod<bool>('requestBluetoothPermissions');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }
}
