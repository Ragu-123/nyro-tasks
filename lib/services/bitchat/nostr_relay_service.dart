import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'bitchat_models.dart';
import 'nostr_crypto.dart';

class RelayHealth {
  final String url;
  bool isConnected;
  DateTime? lastConnectedAt;
  DateTime? lastDisconnectedAt;
  String? lastError;
  int messagesSent;
  int messagesReceived;
  int reconnectAttempts;

  RelayHealth({
    required this.url,
    this.isConnected = false,
    this.lastConnectedAt,
    this.lastDisconnectedAt,
    this.lastError,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.reconnectAttempts = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'is_connected': isConnected,
      'messages_sent': messagesSent,
      'messages_received': messagesReceived,
      'last_error': lastError,
    };
  }
}

class NostrRelayService {
  static final List<String> defaultRelays = [
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://nostr.mom',
    'wss://relay.snort.social',
    'wss://offchain.pub',
    'wss://relay.damus.io',
  ];

  final Map<String, WebSocket> _sockets = {};
  final Map<String, RelayHealth> _relayHealth = {};
  final Map<String, Timer> _reconnectTimers = {};

  static const int seenEventsTtlSeconds = 7200; // 2 hours
  static const int maxSeenEvents = 10000;
  static const int maxFrameBytes = 262144; // 256 KB max per frame
  final Map<String, int> _seenEventTimestamps = {};
  Timer? _cachePruneTimer;

  final StreamController<NostrEvent> _eventController = StreamController<NostrEvent>.broadcast();
  final StreamController<BitchatMessage> _messageController = StreamController<BitchatMessage>.broadcast();
  final ValueNotifier<Map<String, bool>> relayStatusNotifier = ValueNotifier<Map<String, bool>>({});

  final Map<String, Map<String, dynamic>> _activeSubscriptions = {};

  bool _isDisposed = false;
  String? _currentGeohash;
  Timer? _presenceTimer;

  String _devicePrivateKeyHex = '';
  String _devicePublicKeyHex = '';
  String _nickname = 'User';

  Stream<NostrEvent> get eventStream => _eventController.stream;
  Stream<BitchatMessage> get messageStream => _messageController.stream;
  Map<String, RelayHealth> get relayHealth => Map.unmodifiable(_relayHealth);

  void initialize({
    required String privateKeyHex,
    required String publicKeyHex,
    required String nickname,
    List<String>? customRelays,
    bool autoConnect = true,
  }) {
    _devicePrivateKeyHex = privateKeyHex;
    _devicePublicKeyHex = publicKeyHex;
    _nickname = nickname;

    _activeSubscriptions['geo_global'] = {
      'kinds': [20000, 20001, 1],
      '#g': ['global'],
      'limit': 50,
    };
    _activeSubscriptions['geo_gate2027'] = {
      'kinds': [20000, 20001, 1],
      '#g': ['gate2027'],
      'limit': 50,
    };
    _activeSubscriptions['geo_mesh'] = {
      'kinds': [20000, 20001, 1],
      '#g': ['mesh'],
      'limit': 50,
    };

    final relaysToConnect = (customRelays ?? defaultRelays).where(isValidRelayUrl).toList();
    for (final url in relaysToConnect) {
      _relayHealth[url] = RelayHealth(url: url);
    }
    _updateStatusNotifier();
    if (autoConnect) {
      connectAll();
    }

    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _sendGeohashPresenceHeartbeat();
    });

    _cachePruneTimer?.cancel();
    _cachePruneTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _pruneSeenEvents(nowSec);
    });
  }

  static bool isValidRelayUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (!uri.hasScheme || (uri.scheme != 'wss' && uri.scheme != 'ws')) return false;
      if (uri.host.isEmpty) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static String sanitizeContent(String input, {int maxLength = 10000}) {
    if (input.isEmpty) return '';
    final filtered = input
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
        .trim();
    if (filtered.length > maxLength) {
      return filtered.substring(0, maxLength);
    }
    return filtered;
  }

  void _pruneSeenEvents(int nowSec) {
    _seenEventTimestamps.removeWhere((id, ts) => (nowSec - ts) > seenEventsTtlSeconds);
    if (_seenEventTimestamps.length > maxSeenEvents) {
      final sorted = _seenEventTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final excess = sorted.length - maxSeenEvents;
      for (int i = 0; i < excess; i++) {
        _seenEventTimestamps.remove(sorted[i].key);
      }
    }
  }

  void updateIdentity({String? privateKeyHex, String? publicKeyHex, String? nickname}) {
    if (privateKeyHex != null) _devicePrivateKeyHex = privateKeyHex;
    if (publicKeyHex != null) _devicePublicKeyHex = publicKeyHex;
    if (nickname != null) _nickname = nickname;
  }

  void connectAll() {
    if (_isDisposed) return;
    for (final url in _relayHealth.keys) {
      _connectRelay(url);
    }
  }

  void disconnectAll() {
    for (final entry in _sockets.entries) {
      try {
        entry.value.close(WebSocketStatus.normalClosure, 'Client disconnecting');
      } catch (_) {}
    }
    _sockets.clear();
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();

    for (final health in _relayHealth.values) {
      health.isConnected = false;
      health.lastDisconnectedAt = DateTime.now();
    }
    _updateStatusNotifier();
  }

  Future<void> addRelay(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || _relayHealth.containsKey(cleanUrl)) return;

    _relayHealth[cleanUrl] = RelayHealth(url: cleanUrl);
    _updateStatusNotifier();
    _connectRelay(cleanUrl);
  }

  Future<void> removeRelay(String url) async {
    _reconnectTimers[url]?.cancel();
    _reconnectTimers.remove(url);

    final socket = _sockets.remove(url);
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'Removed');
      } catch (_) {}
    }
    _relayHealth.remove(url);
    _updateStatusNotifier();
  }

  Future<void> _connectRelay(String url) async {
    if (_isDisposed) return;
    if (_sockets.containsKey(url)) return;

    final health = _relayHealth[url] ?? RelayHealth(url: url);
    _relayHealth[url] = health;

    try {
      final socket = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
      _sockets[url] = socket;
      health.isConnected = true;
      health.lastConnectedAt = DateTime.now();
      health.lastError = null;
      health.reconnectAttempts = 0;
      _updateStatusNotifier();

      _resubscribeOnRelay(url, socket);

      socket.listen(
        (data) => _handleSocketData(url, data),
        onError: (err) => _handleSocketError(url, err),
        onDone: () => _handleSocketDone(url),
        cancelOnError: true,
      );
    } catch (err) {
      health.isConnected = false;
      health.lastError = err.toString();
      health.lastDisconnectedAt = DateTime.now();
      health.reconnectAttempts++;
      _updateStatusNotifier();
      _scheduleReconnect(url);
    }
  }

  void _scheduleReconnect(String url) {
    if (_isDisposed) return;
    _reconnectTimers[url]?.cancel();

    final health = _relayHealth[url];
    final attempts = health?.reconnectAttempts ?? 1;

    // Exponential backoff policy: base 2s * 1.8^(attempts - 1), capped at 60s
    final baseDelay = min(60.0, 2.0 * pow(1.8, attempts - 1));
    // Add +/- 15% random jitter to avoid thundering herd reconnection storms
    final jitter = (Random().nextDouble() * 0.3 - 0.15) * baseDelay;
    final delaySeconds = (baseDelay + jitter).clamp(2.0, 60.0);

    _reconnectTimers[url] = Timer(Duration(milliseconds: (delaySeconds * 1000).toInt()), () {
      if (!_isDisposed && !_sockets.containsKey(url)) {
        _connectRelay(url);
      }
    });
  }

  void _handleSocketData(String url, dynamic data) {
    if (data is! String) return;
    if (data.length > maxFrameBytes) return; // Strict payload size limit to prevent OOM DoS

    final health = _relayHealth[url];
    if (health != null) health.messagesReceived++;

    try {
      final parsed = jsonDecode(data);
      if (parsed is! List || parsed.isEmpty) return;

      final action = parsed[0] as String;
      if (action == 'EVENT' && parsed.length >= 3) {
        final eventJson = parsed[2] as Map<String, dynamic>;
        final event = NostrEvent.fromJson(eventJson);

        // Security check: validate ID and pubkey hex format
        if (!NostrCrypto.isValidHex(event.id, 64)) return;
        if (!NostrCrypto.isValidHex(event.pubkey, 64)) return;
        if (event.sig != null && !NostrCrypto.isValidHex(event.sig!, 128)) return;

        // Replay and clock skew prevention
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (event.createdAt > nowSec + 600) return; // Future skew > 10m
        if (event.createdAt < nowSec - 604800) return; // Past skew > 7 days

        // Deduplication using TTL cache
        if (_seenEventTimestamps.containsKey(event.id)) return;
        _seenEventTimestamps[event.id] = nowSec;
        if (_seenEventTimestamps.length > maxSeenEvents) {
          _pruneSeenEvents(nowSec);
        }

        // Verify Event ID calculation
        final calculatedId = NostrCrypto.computeEventId(
          pubkey: event.pubkey,
          createdAt: event.createdAt,
          kind: event.kind,
          tags: event.tags,
          content: event.content,
        );
        if (calculatedId != event.id) return; // Event ID forged or tampered

        // Verify Schnorr signature if present
        if (event.sig != null) {
          final isSigValid = NostrCrypto.verifySchnorr(
            msgHashHex: event.id,
            pubkeyHex: event.pubkey,
            sigHex: event.sig!,
          );
          if (!isSigValid) return; // Invalid signature, drop forged event
        }

        _eventController.add(event);
        _processIncomingEvent(event);
      } else if (action == 'NOTICE' && parsed.length >= 2) {
        // Relay informational notice
      } else if (action == 'OK' && parsed.length >= 4) {
        // Publish confirmation
      }
    } catch (_) {}
  }

  void _handleSocketError(String url, dynamic err) {
    final health = _relayHealth[url];
    if (health != null) {
      health.isConnected = false;
      health.lastError = err.toString();
      health.lastDisconnectedAt = DateTime.now();
    }
    _sockets.remove(url);
    _updateStatusNotifier();
    _scheduleReconnect(url);
  }

  void _handleSocketDone(String url) {
    final health = _relayHealth[url];
    if (health != null) {
      health.isConnected = false;
      health.lastDisconnectedAt = DateTime.now();
    }
    _sockets.remove(url);
    _updateStatusNotifier();
    _scheduleReconnect(url);
  }

  void _updateStatusNotifier() {
    final map = <String, bool>{};
    for (final entry in _relayHealth.entries) {
      map[entry.key] = entry.value.isConnected;
    }
    relayStatusNotifier.value = map;
  }

  void subscribeToGeohash(String geohash) {
    _currentGeohash = geohash;
    final subId = 'geo_$geohash';
    final filter = {
      'kinds': [20000, 20001, 1],
      '#g': [geohash],
      'limit': 50,
    };

    _activeSubscriptions[subId] = filter;

    final reqMessage = jsonEncode(['REQ', subId, filter]);
    _broadcastToConnectedSockets(reqMessage);

    _sendGeohashPresenceHeartbeat();
  }

  void unsubscribeFromGeohash(String geohash) {
    final subId = 'geo_$geohash';
    _activeSubscriptions.remove(subId);
    final closeMessage = jsonEncode(['CLOSE', subId]);
    _broadcastToConnectedSockets(closeMessage);
  }

  void subscribeToDirectMessages(String myNostrPubkeyHex) {
    final subId = 'dm_$myNostrPubkeyHex';
    final filter = {
      'kinds': [1059, 14, 4],
      '#p': [myNostrPubkeyHex],
      'limit': 50,
    };

    _activeSubscriptions[subId] = filter;
    final reqMessage = jsonEncode(['REQ', subId, filter]);
    _broadcastToConnectedSockets(reqMessage);
  }

  void _resubscribeOnRelay(String url, WebSocket socket) {
    for (final entry in _activeSubscriptions.entries) {
      try {
        final reqMsg = jsonEncode(['REQ', entry.key, entry.value]);
        socket.add(reqMsg);
      } catch (_) {}
    }
  }

  void _broadcastToConnectedSockets(String message) {
    for (final entry in _sockets.entries) {
      try {
        entry.value.add(message);
        final health = _relayHealth[entry.key];
        if (health != null) health.messagesSent++;
      } catch (_) {}
    }
  }

  Future<NostrEvent?> publishEphemeralGeohashMessage({
    required String geohash,
    required String content,
    String? nickname,
  }) async {
    if (_devicePrivateKeyHex.isEmpty || _devicePublicKeyHex.isEmpty) return null;

    final senderNick = nickname ?? _nickname;
    final tags = [
      ['g', geohash],
      ['n', senderNick],
    ];

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final eventId = NostrCrypto.computeEventId(
      pubkey: _devicePublicKeyHex,
      createdAt: nowSec,
      kind: 20000,
      tags: tags,
      content: content,
    );

    final sig = NostrCrypto.signSchnorr(eventId, _devicePrivateKeyHex);

    final event = NostrEvent(
      id: eventId,
      pubkey: _devicePublicKeyHex,
      createdAt: nowSec,
      kind: 20000,
      tags: tags,
      content: content,
      sig: sig,
    );

    final eventJson = jsonEncode(['EVENT', event.toJson()]);
    _broadcastToConnectedSockets(eventJson);

    final message = BitchatMessage(
      id: eventId,
      sender: senderNick,
      senderPeerID: _devicePublicKeyHex.length >= 16 ? _devicePublicKeyHex.substring(0, 16) : _devicePublicKeyHex,
      senderNostrPubkey: _devicePublicKeyHex,
      content: content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(nowSec * 1000),
      channel: 'geo:$geohash',
      isPrivate: false,
      isRelay: true,
      deliveryStatus: DeliveryStatus.sent,
      transportType: TransportType.relay,
    );
    _messageController.add(message);

    return event;
  }

  Future<void> _sendGeohashPresenceHeartbeat() async {
    if (_currentGeohash == null || _devicePrivateKeyHex.isEmpty || _devicePublicKeyHex.isEmpty) return;

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tags = [
      ['g', _currentGeohash!],
    ];

    final eventId = NostrCrypto.computeEventId(
      pubkey: _devicePublicKeyHex,
      createdAt: nowSec,
      kind: 20001,
      tags: tags,
      content: '',
    );

    final sig = NostrCrypto.signSchnorr(eventId, _devicePrivateKeyHex);

    final event = NostrEvent(
      id: eventId,
      pubkey: _devicePublicKeyHex,
      createdAt: nowSec,
      kind: 20001,
      tags: tags,
      content: '',
      sig: sig,
    );

    final eventJson = jsonEncode(['EVENT', event.toJson()]);
    _broadcastToConnectedSockets(eventJson);
  }

  Future<NostrEvent?> publishDirectMessage({
    required String recipientPubkeyHex,
    required String content,
    String? recipientNickname,
  }) async {
    if (_devicePrivateKeyHex.isEmpty || _devicePublicKeyHex.isEmpty) return null;

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tags = [
      ['p', recipientPubkeyHex],
    ];

    final eventId = NostrCrypto.computeEventId(
      pubkey: _devicePublicKeyHex,
      createdAt: nowSec,
      kind: 14,
      tags: tags,
      content: content,
    );

    final sig = NostrCrypto.signSchnorr(eventId, _devicePrivateKeyHex);

    final event = NostrEvent(
      id: eventId,
      pubkey: _devicePublicKeyHex,
      createdAt: nowSec,
      kind: 14,
      tags: tags,
      content: content,
      sig: sig,
    );

    final eventJson = jsonEncode(['EVENT', event.toJson()]);
    _broadcastToConnectedSockets(eventJson);

    final message = BitchatMessage(
      id: eventId,
      sender: _nickname,
      senderPeerID: _devicePublicKeyHex.length >= 16 ? _devicePublicKeyHex.substring(0, 16) : _devicePublicKeyHex,
      senderNostrPubkey: _devicePublicKeyHex,
      recipientNickname: recipientNickname,
      content: content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(nowSec * 1000),
      channel: 'dm:$recipientPubkeyHex',
      isPrivate: true,
      isRelay: true,
      deliveryStatus: DeliveryStatus.sent,
      transportType: TransportType.relay,
    );
    _messageController.add(message);

    return event;
  }

  void _processIncomingEvent(NostrEvent event) {
    final cleanContent = sanitizeContent(event.content);
    if (cleanContent.isEmpty && event.kind != 20001) return;

    if (event.kind == 20000 || event.kind == 1) {
      String? geohash;
      String senderNick = 'Anonymous';

      for (final tag in event.tags) {
        if (tag.isNotEmpty) {
          if (tag[0] == 'g' && tag.length > 1) {
            geohash = tag[1];
          } else if (tag[0] == 'n' && tag.length > 1) {
            senderNick = tag[1];
          }
        }
      }

      final cleanNick = sanitizeContent(senderNick, maxLength: 40);
      final safeNick = cleanNick.isNotEmpty ? cleanNick : 'Anonymous';
      final cleanGeohash = geohash != null ? sanitizeContent(geohash, maxLength: 32).toLowerCase() : null;
      final String channelId;
      if (cleanGeohash == 'mesh') {
        channelId = 'mesh';
      } else if (cleanGeohash != null && cleanGeohash.isNotEmpty) {
        channelId = 'geo:$cleanGeohash';
      } else {
        channelId = 'geo:global';
      }
      final peerId = event.pubkey.length >= 16 ? event.pubkey.substring(0, 16) : event.pubkey;

      final message = BitchatMessage(
        id: event.id,
        sender: safeNick,
        senderPeerID: peerId,
        senderNostrPubkey: event.pubkey,
        content: cleanContent,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        channel: channelId,
        isPrivate: false,
        isRelay: true,
        deliveryStatus: DeliveryStatus.delivered,
        transportType: TransportType.relay,
      );
      _messageController.add(message);
    } else if (event.kind == 14 || event.kind == 4) {
      String? recipientPubkey;
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          recipientPubkey = tag[1];
        }
      }

      final peerId = event.pubkey.length >= 16 ? event.pubkey.substring(0, 16) : event.pubkey;
      final cleanRecipient = recipientPubkey != null ? sanitizeContent(recipientPubkey, maxLength: 64) : null;

      final message = BitchatMessage(
        id: event.id,
        sender: 'Peer_${peerId.substring(0, min(6, peerId.length))}',
        senderPeerID: peerId,
        senderNostrPubkey: event.pubkey,
        recipientNickname: cleanRecipient,
        content: cleanContent,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        channel: 'dm:${event.pubkey}',
        isPrivate: true,
        isRelay: true,
        deliveryStatus: DeliveryStatus.delivered,
        transportType: TransportType.relay,
      );
      _messageController.add(message);
    }
  }

  void dispose() {
    _isDisposed = true;
    _presenceTimer?.cancel();
    _cachePruneTimer?.cancel();
    _seenEventTimestamps.clear();
    disconnectAll();
    _eventController.close();
    _messageController.close();
    relayStatusNotifier.dispose();
  }
}
