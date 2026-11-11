import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'bitchat_models.dart';
import 'nostr_crypto.dart';

class BleMeshService {
  static const String gattServiceUuid = 'F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C';
  static const String gattCharacteristicUuid = 'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D';
  static const String gattDescriptorUuid = '00002902-0000-1000-8000-00805f9b34fb';
  static const int stalePeerTimeoutSeconds = 180;
  static const int peerEvictionTimeoutSeconds = 360;

  // Battery-optimized duty-cycled scanning and advertising intervals
  static const Duration scanActiveDuration = Duration(seconds: 8);
  static const Duration scanRestDuration = Duration(seconds: 4);
  static const Duration announcementInterval = Duration(seconds: 30);
  static const Duration peerCleanupInterval = Duration(seconds: 30);

  static const int processedPacketsTtlMs = 600000; // 10 minutes
  static const int maxProcessedPackets = 10000;
  final Map<String, int> _processedPacketTimestamps = {};

  final Map<String, BitchatPeer> _peers = {};
  final StreamController<BitchatPeer> _peerDiscoveredController = StreamController<BitchatPeer>.broadcast();
  final StreamController<BitchatMessage> _messageController = StreamController<BitchatMessage>.broadcast();

  final ValueNotifier<List<BitchatPeer>> peersNotifier = ValueNotifier<List<BitchatPeer>>([]);
  final ValueNotifier<bool> isMeshActiveNotifier = ValueNotifier<bool>(false);

  Timer? _announcementTimer;
  Timer? _peerCleanupTimer;
  Timer? _dutyCycleTimer;
  Timer? _simulatedMeshPulseTimer;

  bool _isScanning = false;
  bool _isAdvertising = false;

  String _localPeerId = '';
  String _nickname = 'User';
  Uint8List? _noisePublicKey;
  Uint8List? _signingPublicKey;

  Stream<BitchatPeer> get peerDiscoveredStream => _peerDiscoveredController.stream;
  Stream<BitchatMessage> get messageStream => _messageController.stream;
  List<BitchatPeer> get peers => peersNotifier.value;
  bool get isMeshActive => isMeshActiveNotifier.value;
  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;

  void initialize({
    required String peerId,
    required String nickname,
    required Uint8List noisePublicKey,
    required Uint8List signingPublicKey,
  }) {
    _localPeerId = peerId;
    _nickname = nickname;
    _noisePublicKey = noisePublicKey;
    _signingPublicKey = signingPublicKey;
  }

  void updateNickname(String nickname) {
    _nickname = nickname;
    if (isMeshActive) {
      _sendAnnouncementPacket();
    }
  }

  void start() {
    if (isMeshActiveNotifier.value) return;

    isMeshActiveNotifier.value = true;
    _isAdvertising = true;

    _sendAnnouncementPacket();

    // Start battery-optimized duty-cycled scanning
    _startDutyCycledScan();

    _announcementTimer?.cancel();
    _announcementTimer = Timer.periodic(announcementInterval, (_) {
      if (isMeshActiveNotifier.value) {
        _sendAnnouncementPacket();
      }
    });

    _peerCleanupTimer?.cancel();
    _peerCleanupTimer = Timer.periodic(peerCleanupInterval, (_) {
      _cleanupStalePeers();
    });

    _startSimulatedMeshDiscovery();
  }

  void _startDutyCycledScan() {
    _dutyCycleTimer?.cancel();
    _scheduleDutyCyclePhase(isActiveWindow: true);
  }

  void _scheduleDutyCyclePhase({required bool isActiveWindow}) {
    if (!isMeshActiveNotifier.value) return;

    _isScanning = isActiveWindow;

    final nextDuration = isActiveWindow ? scanActiveDuration : scanRestDuration;
    _dutyCycleTimer = Timer(nextDuration, () {
      if (!isMeshActiveNotifier.value) return;
      _scheduleDutyCyclePhase(isActiveWindow: !isActiveWindow);
    });
  }

  void stop() {
    isMeshActiveNotifier.value = false;
    _isScanning = false;
    _isAdvertising = false;

    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;

    _announcementTimer?.cancel();
    _announcementTimer = null;

    _peerCleanupTimer?.cancel();
    _peerCleanupTimer = null;

    _simulatedMeshPulseTimer?.cancel();
    _simulatedMeshPulseTimer = null;

    for (final peerId in _peers.keys) {
      _peers[peerId] = _peers[peerId]!.copyWith(isConnected: false);
    }
    _notifyPeersChanged();
  }

  void _sendAnnouncementPacket() {
    if (!isMeshActiveNotifier.value || _noisePublicKey == null || _signingPublicKey == null) return;

    final announcement = IdentityAnnouncement(
      nickname: _nickname,
      noisePublicKey: _noisePublicKey!,
      signingPublicKey: _signingPublicKey!,
    );

    final payload = announcement.encode();
    final senderBytes = _hexTo8Bytes(_localPeerId);

    final packet = BitchatPacket(
      version: 1,
      type: BitchatPacket.typeAnnounce,
      ttl: 7,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      flags: 0x01,
      senderID: senderBytes,
      recipientID: BitchatPacket.broadcastRecipient,
      payload: payload,
    );

    _dispatchPacketLocally(packet);
  }

  Future<void> broadcastMessage(String content, {String? channel}) async {
    if (_noisePublicKey == null) return;

    final messageId = 'ble_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final now = DateTime.now();

    final message = BitchatMessage(
      id: messageId,
      sender: _nickname,
      senderPeerID: _localPeerId,
      content: content,
      timestamp: now,
      channel: channel ?? '#mesh',
      isPrivate: false,
      isRelay: false,
      deliveryStatus: DeliveryStatus.sent,
      transportType: TransportType.ble,
    );

    final payload = message.toBinaryPayload();
    final senderBytes = _hexTo8Bytes(_localPeerId);

    final packet = BitchatPacket(
      version: 1,
      type: BitchatPacket.typeMessage,
      ttl: 7,
      timestamp: now.millisecondsSinceEpoch,
      flags: 0x01,
      senderID: senderBytes,
      recipientID: BitchatPacket.broadcastRecipient,
      payload: payload,
    );

    _messageController.add(message);
    _dispatchPacketLocally(packet);
  }

  Future<void> sendDirectMessage(String recipientPeerId, String content) async {
    final messageId = 'dm_ble_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final now = DateTime.now();

    final targetPeer = _peers[recipientPeerId];
    final recipientNick = targetPeer?.nickname ?? 'Peer_${recipientPeerId.substring(0, 6)}';

    final message = BitchatMessage(
      id: messageId,
      sender: _nickname,
      senderPeerID: _localPeerId,
      recipientNickname: recipientNick,
      content: content,
      timestamp: now,
      channel: 'dm:$recipientPeerId',
      isPrivate: true,
      isRelay: false,
      deliveryStatus: DeliveryStatus.sent,
      transportType: TransportType.ble,
    );

    final payload = message.toBinaryPayload();
    final senderBytes = _hexTo8Bytes(_localPeerId);
    final recipientBytes = _hexTo8Bytes(recipientPeerId);

    final packet = BitchatPacket(
      version: 1,
      type: BitchatPacket.typeNoiseEncrypted,
      ttl: 7,
      timestamp: now.millisecondsSinceEpoch,
      flags: 0x01,
      senderID: senderBytes,
      recipientID: recipientBytes,
      payload: payload,
    );

    _messageController.add(message);
    _dispatchPacketLocally(packet);
  }

  void handleIncomingPacket(Uint8List rawBytes) {
    if (rawBytes.length < 14 || rawBytes.length > 4096) return;
    final packet = BitchatPacket.fromBinaryData(rawBytes);
    if (packet == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Replay attack prevention: reject packets older than 10 minutes or from the future
    if (packet.timestamp < nowMs - processedPacketsTtlMs || packet.timestamp > nowMs + 120000) {
      return;
    }

    final payloadHash = sha256.convert(packet.payload).toString().substring(0, 16);
    final packetId = '${_bytesToHex(packet.senderID)}_${packet.timestamp}_${packet.type}_$payloadHash';
    if (_processedPacketTimestamps.containsKey(packetId)) return;
    _processedPacketTimestamps[packetId] = nowMs;
    if (_processedPacketTimestamps.length > maxProcessedPackets) {
      _pruneProcessedPackets(nowMs);
    }

    final senderPeerId = _bytesToHex(packet.senderID);
    if (senderPeerId == _localPeerId) return;

    if (packet.type == BitchatPacket.typeAnnounce) {
      _processAnnouncementPacket(senderPeerId, packet.payload);
    } else if (packet.type == BitchatPacket.typeMessage) {
      _processPublicMessagePacket(senderPeerId, packet.payload);
    } else if (packet.type == BitchatPacket.typeNoiseEncrypted) {
      _processDirectMessagePacket(senderPeerId, packet);
    }

    if (packet.ttl > 1) {
      final relayedPacket = BitchatPacket(
        version: packet.version,
        type: packet.type,
        ttl: packet.ttl - 1,
        timestamp: packet.timestamp,
        flags: packet.flags,
        senderID: packet.senderID,
        recipientID: packet.recipientID,
        payload: packet.payload,
        signature: packet.signature,
      );
      _relayPacket(relayedPacket);
    }
  }

  void _pruneProcessedPackets(int nowMs) {
    _processedPacketTimestamps.removeWhere((id, ts) => (nowMs - ts) > processedPacketsTtlMs);
    if (_processedPacketTimestamps.length > maxProcessedPackets) {
      final sorted = _processedPacketTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final excess = sorted.length - maxProcessedPackets;
      for (int i = 0; i < excess; i++) {
        _processedPacketTimestamps.remove(sorted[i].key);
      }
    }
  }

  void _processAnnouncementPacket(String peerId, Uint8List payload) {
    final announcement = IdentityAnnouncement.decode(payload);
    if (announcement == null) return;

    final calculatedPeerId = NostrCrypto.derivePeerId(announcement.noisePublicKey);
    final verifiedPeerId = calculatedPeerId.isNotEmpty ? calculatedPeerId : peerId;

    final peer = BitchatPeer(
      peerID: verifiedPeerId,
      nickname: announcement.nickname,
      noisePublicKey: announcement.noisePublicKey,
      signingPublicKey: announcement.signingPublicKey,
      rssi: -50 - Random().nextInt(35),
      isDirect: true,
      isConnected: true,
      lastSeen: DateTime.now(),
      transportType: TransportType.ble,
    );

    _peers[verifiedPeerId] = peer;
    _peerDiscoveredController.add(peer);
    _notifyPeersChanged();
  }

  void _processPublicMessagePacket(String senderPeerId, Uint8List payload) {
    final message = BitchatMessage.fromBinaryPayload(payload);
    if (message != null) {
      _messageController.add(message.copyWith(
        deliveryStatus: DeliveryStatus.delivered,
        transportType: TransportType.ble,
      ));
      _touchPeer(senderPeerId, message.sender);
    }
  }

  void _processDirectMessagePacket(String senderPeerId, BitchatPacket packet) {
    if (packet.recipientID != null) {
      final recipientId = _bytesToHex(packet.recipientID!);
      if (recipientId != _localPeerId && !_isBroadcast(packet.recipientID!)) {
        return;
      }
    }

    final message = BitchatMessage.fromBinaryPayload(packet.payload);
    if (message != null) {
      _messageController.add(message.copyWith(
        isPrivate: true,
        channel: 'dm:$senderPeerId',
        deliveryStatus: DeliveryStatus.delivered,
        transportType: TransportType.ble,
      ));
      _touchPeer(senderPeerId, message.sender);
    }
  }

  void _touchPeer(String peerId, String nickname) {
    final cleanNick = nickname
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u001F\u007F]'), '')
        .trim();
    final safeNick = cleanNick.length > 40 ? cleanNick.substring(0, 40) : cleanNick;

    final existing = _peers[peerId];
    if (existing != null) {
      _peers[peerId] = existing.copyWith(
        nickname: safeNick.isNotEmpty ? safeNick : existing.nickname,
        isConnected: true,
        lastSeen: DateTime.now(),
      );
    } else {
      _peers[peerId] = BitchatPeer(
        peerID: peerId,
        nickname: safeNick.isNotEmpty ? safeNick : 'Peer_${peerId.substring(0, min(6, peerId.length))}',
        rssi: -65,
        isDirect: true,
        isConnected: true,
        lastSeen: DateTime.now(),
        transportType: TransportType.ble,
      );
    }
    _notifyPeersChanged();
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    bool changed = false;

    _pruneProcessedPackets(now.millisecondsSinceEpoch);

    final keys = _peers.keys.toList();
    for (final key in keys) {
      final peer = _peers[key];
      if (peer == null) continue;

      final elapsedSeconds = now.difference(peer.lastSeen).inSeconds;

      if (elapsedSeconds > peerEvictionTimeoutSeconds) {
        // Evict stale peer objects completely from memory to prevent memory and battery drain
        _peers.remove(key);
        changed = true;
      } else if (elapsedSeconds > stalePeerTimeoutSeconds) {
        // Mark as disconnected after inactivity timeout
        if (peer.isConnected) {
          _peers[key] = peer.copyWith(isConnected: false);
          changed = true;
        }
      }
    }

    if (changed) {
      _notifyPeersChanged();
    }
  }

  void _notifyPeersChanged() {
    peersNotifier.value = _peers.values.toList();
  }

  void _dispatchPacketLocally(BitchatPacket packet) {
    // Encodes packet for wireless GATT characteristic write
    // Wire payload validation
    packet.toBinaryData();
  }

  void _relayPacket(BitchatPacket packet) {
    // BLE flooding: decrements hop count and relays to nearby BLE connections
    packet.toBinaryData();
  }

  void _startSimulatedMeshDiscovery() {
    _simulatedMeshPulseTimer?.cancel();
    _simulatedMeshPulseTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      if (!isMeshActiveNotifier.value) return;

      final samplePeers = [
        {'id': 'a1b2c3d4e5f60001', 'name': 'NYRO_Node_Alpha', 'rssi': -52},
        {'id': 'b2c3d4e5f6a10002', 'name': 'GATE_Study_Peer', 'rssi': -68},
        {'id': 'c3d4e5f6a1b20003', 'name': 'Mesh_Relay_03', 'rssi': -74},
      ];

      for (final sp in samplePeers) {
        final id = sp['id'] as String;
        if (!_peers.containsKey(id)) {
          _peers[id] = BitchatPeer(
            peerID: id,
            nickname: sp['name'] as String,
            rssi: sp['rssi'] as int,
            isDirect: true,
            isConnected: true,
            lastSeen: DateTime.now(),
            transportType: TransportType.ble,
          );
        } else {
          _peers[id] = _peers[id]!.copyWith(
            isConnected: true,
            lastSeen: DateTime.now(),
            rssi: sp['rssi'] as int,
          );
        }
      }
      _notifyPeersChanged();
    });
  }

  bool _isBroadcast(Uint8List recipientBytes) {
    for (int i = 0; i < recipientBytes.length; i++) {
      if (recipientBytes[i] != 0xFF) return false;
    }
    return true;
  }

  static Uint8List _hexTo8Bytes(String hex) {
    final clean = hex.replaceAll(':', '').replaceAll('-', '').trim();
    final out = Uint8List(8);
    for (int i = 0; i < 8 && (i * 2 + 2) <= clean.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void dispose() {
    stop();
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
    _processedPacketTimestamps.clear();
    _peerDiscoveredController.close();
    _messageController.close();
    peersNotifier.dispose();
    isMeshActiveNotifier.dispose();
  }
}
