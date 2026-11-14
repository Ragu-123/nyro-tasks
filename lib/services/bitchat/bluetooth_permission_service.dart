import 'package:flutter/services.dart';

class BluetoothPermissionService {
  static const MethodChannel _btChannel = MethodChannel('io.github.thelazyindian.tasks/bluetooth_permissions');
  static const MethodChannel _nativeChannel = MethodChannel('io.github.thelazyindian.tasks/native');

  static Future<bool> checkPermissions() async {
    try {
      final bool? granted = await _btChannel.invokeMethod<bool>('checkBluetoothPermissions');
      if (granted != null) return granted;
      return await _nativeChannel.invokeMethod<bool>('checkBluetoothPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermissions() async {
    try {
      final bool? granted = await _btChannel.invokeMethod<bool>('requestBluetoothPermissions');
      if (granted != null) return granted;
      return await _nativeChannel.invokeMethod<bool>('requestBluetoothPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }
}
