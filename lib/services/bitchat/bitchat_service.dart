import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../data/database_service.dart';
import 'bitchat_models.dart';
import 'ble_mesh_service.dart';
import 'bluetooth_permission_service.dart';
import 'nostr_crypto.dart';
import 'nostr_relay_service.dart';

class BitchatService {
  static final BitchatService instance = BitchatService._internal();
  BitchatService._internal();

  static const int maxMessagesPerChannel = 500;
  static const int maxDeduplicationCacheSize = 5000;

  final BleMeshService bleMeshService = BleMeshService();
  final NostrRelayService nostrRelayService = NostrRelayService();
  final DatabaseService _db = DatabaseService.instance;

  final StreamController<BitchatMessage> _unifiedMessageController =
      StreamController<BitchatMessage>.broadcast();

  final ValueNotifier<BitchatChannel?> activeChannelNotifier = ValueNotifier<BitchatChannel?>(null);
  final ValueNotifier<List<BitchatChannel>> channelsNotifier = ValueNotifier<List<BitchatChannel>>([]);
  final ValueNotifier<List<BitchatMessage>> currentChannelMessagesNotifier =
      ValueNotifier<List<BitchatMessage>>([]);

  final ValueNotifier<String> currentNicknameNotifier = ValueNotifier<String>('NYRO_User');
  final ValueNotifier<String> currentPeerIdNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> currentNpubNotifier = ValueNotifier<String>('');

  ValueNotifier<List<BitchatPeer>> get peersNotifier => bleMeshService.peersNotifier;
  ValueNotifier<Map<String, bool>> get relayStatusNotifier => nostrRelayService.relayStatusNotifier;
  ValueNotifier<bool> get bleMeshActiveNotifier => bleMeshService.isMeshActiveNotifier;

  Stream<BitchatMessage> get messageStream => _unifiedMessageController.stream;

  final Map<String, List<BitchatMessage>> _channelMessages = {};
  final Set<String> _seenMessageIds = {};
  final List<BitchatChannel> _channels = [];

  String _nickname = 'NYRO_User';
  String _peerId = '';
  String _noisePrivateKeyHex = '';
  Uint8List _noisePublicKey = Uint8List(32);
  Uint8List _signingPublicKey = Uint8List(32);
  String _nostrPrivateKeyHex = '';
  String _nostrPublicKeyHex = '';
  String _nostrNpub = '';
  String _currentGeohash = 'gate2027';

  bool _initialized = false;
  StreamSubscription<BitchatMessage>? _bleSub;
  StreamSubscription<BitchatMessage>? _nostrSub;
  StreamSubscription<BitchatPeer>? _peerSub;

  String get nickname => _nickname;
  String get peerId => _peerId;
  String get npub => _nostrNpub;
  String get currentGeohash => _currentGeohash;
  BitchatChannel? get activeChannel => activeChannelNotifier.value;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await BluetoothPermissionService.requestPermissions();

    await _loadOrGenerateIdentity();
    await _loadChannels();
    await _loadStoredMessages();

    bleMeshService.initialize(
      peerId: _peerId,
      nickname: _nickname,
      noisePublicKey: _noisePublicKey,
      signingPublicKey: _signingPublicKey,
    );

    nostrRelayService.initialize(
      privateKeyHex: _nostrPrivateKeyHex,
      publicKeyHex: _nostrPublicKeyHex,
      nickname: _nickname,
    );

    bleMeshService.start();

    _bleSub = bleMeshService.messageStream.listen(_onIncomingMessage);
    _nostrSub = nostrRelayService.messageStream.listen(_onIncomingMessage);
    _peerSub = bleMeshService.peerDiscoveredStream.listen(_onPeerDiscovered);

    if (_channels.isNotEmpty) {
      await selectChannel(_channels.first.id);
    }
  }

  Future<void> _loadOrGenerateIdentity() async {
    final savedNick = await _db.getConfig('bitchat_nickname');
    if (savedNick != null && savedNick.isNotEmpty) {
      final clean = savedNick
          .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u001F\u007F]'), '')
          .trim();
      _nickname = clean.length > 40 ? clean.substring(0, 40) : (clean.isNotEmpty ? clean : 'NYRO_User');
    } else {
      _nickname = 'User_${Random().nextInt(9000) + 1000}';
      await _db.setConfig('bitchat_nickname', _nickname);
    }
    currentNicknameNotifier.value = _nickname;

    var privHex = await _db.getConfig('bitchat_noise_priv');
    if (privHex == null || privHex.length < 64 || !NostrCrypto.isValidPrivateKeyHex(privHex)) {
      privHex = NostrCrypto.generatePrivateKey();
      await _db.setConfig('bitchat_noise_priv', privHex);
    }
    _noisePrivateKeyHex = privHex;

    final pubHex = NostrCrypto.derivePublicKey(_noisePrivateKeyHex);
    _noisePublicKey = _hexToBytes(pubHex);
    _signingPublicKey = _hexToBytes(pubHex);

    _peerId = NostrCrypto.derivePeerId(_noisePublicKey);
    await _db.setConfig('bitchat_peer_id', _peerId);
    currentPeerIdNotifier.value = _peerId;

    var nostrPriv = await _db.getConfig('bitchat_nostr_priv');
    if (nostrPriv == null || nostrPriv.length < 64 || !NostrCrypto.isValidPrivateKeyHex(nostrPriv)) {
      nostrPriv = NostrCrypto.generatePrivateKey();
      await _db.setConfig('bitchat_nostr_priv', nostrPriv);
    }
    _nostrPrivateKeyHex = nostrPriv;
    _nostrPublicKeyHex = NostrCrypto.derivePublicKey(_nostrPrivateKeyHex);
    _nostrNpub = NostrCrypto.encodeNpub(_nostrPublicKeyHex);
    await _db.setConfig('bitchat_nostr_pubkey', _nostrPublicKeyHex);
    await _db.setConfig('bitchat_nostr_npub', _nostrNpub);
    currentNpubNotifier.value = _nostrNpub;

    final savedGeohash = await _db.getConfig('bitchat_geohash');
    if (savedGeohash != null && savedGeohash.isNotEmpty) {
      final cleanGeo = savedGeohash.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '').trim().toLowerCase();
      if (cleanGeo.isNotEmpty) {
        _currentGeohash = cleanGeo;
      }
    }
  }

  Future<void> _loadChannels() async {
    _channels.clear();

    final stored = await _db.getBitchatChannels();
    if (stored.isNotEmpty) {
      for (final row in stored) {
        _channels.add(BitchatChannel.fromMap(row));
      }
    } else {
      final defaultMesh = const BitchatChannel(
        id: 'mesh',
        name: '#mesh (BLE Broadcast)',
        type: ChannelType.broadcast,
      );
      final defaultGate = const BitchatChannel(
        id: 'geo:gate2027',
        name: '#gate2027 (Study Group)',
        type: ChannelType.geohash,
        geohash: 'gate2027',
      );
      final defaultGlobal = const BitchatChannel(
        id: 'geo:global',
        name: '#global (Nostr Geohash)',
        type: ChannelType.geohash,
        geohash: 'global',
      );

      _channels.addAll([defaultMesh, defaultGate, defaultGlobal]);
      for (final ch in _channels) {
        await _db.upsertBitchatChannel(ch.toMap());
      }
    }

    channelsNotifier.value = List.unmodifiable(_channels);
  }

  Future<void> _loadStoredMessages() async {
    final stored = await _db.getBitchatMessages(limit: 500);
    for (final row in stored) {
      final msg = BitchatMessage.fromMap(row);
      final chId = msg.channel ?? 'mesh';
      final list = _channelMessages.putIfAbsent(chId, () => []);
      if (list.length < maxMessagesPerChannel) {
        list.add(msg);
      }
      _seenMessageIds.add(msg.id);
    }
  }

  Future<void> selectChannel(String channelId) async {
    final idx = _channels.indexWhere((c) => c.id == channelId);
    if (idx == -1) return;

    final selected = _channels[idx];
    activeChannelNotifier.value = selected;

    if (selected.unreadCount > 0) {
      final updated = selected.copyWith(unreadCount: 0);
      _channels[idx] = updated;
      channelsNotifier.value = List.unmodifiable(_channels);
      await _db.upsertBitchatChannel(updated.toMap());
    }

    final msgs = _channelMessages[channelId] ?? [];
    currentChannelMessagesNotifier.value = List.unmodifiable(msgs);

    if (selected.type == ChannelType.geohash && selected.geohash != null) {
      nostrRelayService.subscribeToGeohash(selected.geohash!);
    }
  }

  Future<void> sendMessage(String text) async {
    final sanitized = text
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
        .trim();
    if (sanitized.isEmpty) return;
    final cleanContent = sanitized.length > 10000 ? sanitized.substring(0, 10000) : sanitized;

    final currentChannel = activeChannelNotifier.value;
    if (currentChannel == null) return;

    if (currentChannel.id == 'mesh' || currentChannel.type == ChannelType.broadcast) {
      // Dual-transport multi-dispatch: broadcast to local BLE mesh and publish to Nostr relays
      await bleMeshService.broadcastMessage(cleanContent, channel: currentChannel.id);
      await nostrRelayService.publishEphemeralGeohashMessage(
        geohash: 'mesh',
        content: cleanContent,
        nickname: _nickname,
      );
    } else if (currentChannel.type == ChannelType.geohash && currentChannel.geohash != null) {
      // Dual-transport multi-dispatch: publish to Nostr relays and broadcast to local BLE mesh
      await bleMeshService.broadcastMessage(cleanContent, channel: currentChannel.id);
      await nostrRelayService.publishEphemeralGeohashMessage(
        geohash: currentChannel.geohash!,
        content: cleanContent,
        nickname: _nickname,
      );
    } else if (currentChannel.type == ChannelType.direct) {
      final peerId = currentChannel.id.replaceFirst('dm:', '');
      final isBlePeer = bleMeshService.peers.any((p) => p.peerID == peerId && p.isConnected);

      if (isBlePeer) {
        await bleMeshService.sendDirectMessage(peerId, cleanContent);
      }
      // Also multi-dispatch direct message via Nostr relay so the recipient receives it across networks
      await nostrRelayService.publishDirectMessage(
        recipientPubkeyHex: peerId,
        content: cleanContent,
        recipientNickname: currentChannel.name,
      );
    }
  }

  Future<void> _onIncomingMessage(BitchatMessage message) async {
    final chId = message.channel ?? 'mesh';
    _channelMessages.putIfAbsent(chId, () => []);

    // Instant O(1) deduplication check using bounded FIFO Set
    if (_seenMessageIds.contains(message.id)) {
      return;
    }
    if (_seenMessageIds.length >= maxDeduplicationCacheSize) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }
    _seenMessageIds.add(message.id);

    final list = _channelMessages[chId]!;
    list.add(message);

    // Enforce bounded in-memory message history (max 500 per channel in memory)
    if (list.length > maxMessagesPerChannel) {
      list.removeRange(0, list.length - maxMessagesPerChannel);
    }

    await _db.insertBitchatMessage(message.toMap());

    final isActive = activeChannelNotifier.value?.id == chId;
    if (isActive) {
      currentChannelMessagesNotifier.value = List.unmodifiable(list);
    }

    final chIdx = _channels.indexWhere((c) => c.id == chId);
    if (chIdx != -1) {
      final ch = _channels[chIdx];
      final unread = isActive ? 0 : ch.unreadCount + 1;
      final updated = ch.copyWith(
        unreadCount: unread,
        lastMessage: message,
      );
      _channels[chIdx] = updated;
      channelsNotifier.value = List.unmodifiable(_channels);
      await _db.upsertBitchatChannel(updated.toMap());
    } else if (message.isPrivate) {
      final newDmChannel = BitchatChannel(
        id: chId,
        name: message.sender,
        type: ChannelType.direct,
        unreadCount: isActive ? 0 : 1,
        lastMessage: message,
      );
      _channels.add(newDmChannel);
      channelsNotifier.value = List.unmodifiable(_channels);
      await _db.upsertBitchatChannel(newDmChannel.toMap());
    }

    _unifiedMessageController.add(message);
  }

  void _onPeerDiscovered(BitchatPeer peer) {
    _db.upsertBitchatPeer(peer.toMap());
  }

  Future<void> setNickname(String newNickname) async {
    final clean = newNickname
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u001F\u007F]'), '')
        .trim();
    if (clean.isEmpty) return;
    final safeNick = clean.length > 40 ? clean.substring(0, 40) : clean;

    _nickname = safeNick;
    await _db.setConfig('bitchat_nickname', safeNick);
    currentNicknameNotifier.value = safeNick;

    bleMeshService.updateNickname(safeNick);
    nostrRelayService.updateIdentity(nickname: safeNick);
  }

  Future<void> addChannel(String name, ChannelType type, {String? geohash}) async {
    final cleanName = name
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u001F\u007F]'), '')
        .trim();
    if (cleanName.isEmpty) return;
    final safeName = cleanName.length > 50 ? cleanName.substring(0, 50) : cleanName;

    final cleanGeohash = geohash != null
        ? geohash.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '').trim().toLowerCase()
        : null;

    final id = type == ChannelType.geohash
        ? 'geo:${(cleanGeohash != null && cleanGeohash.isNotEmpty) ? cleanGeohash : safeName.toLowerCase()}'
        : 'ch_${safeName.toLowerCase().replaceAll(' ', '_')}';

    if (_channels.any((c) => c.id == id)) return;

    final newChannel = BitchatChannel(
      id: id,
      name: safeName,
      type: type,
      geohash: cleanGeohash,
    );

    _channels.add(newChannel);
    channelsNotifier.value = List.unmodifiable(_channels);
    await _db.upsertBitchatChannel(newChannel.toMap());
    await selectChannel(id);
  }

  Future<void> openDirectMessageWithPeer(BitchatPeer peer) async {
    final dmId = 'dm:${peer.peerID}';
    final existingIdx = _channels.indexWhere((c) => c.id == dmId);

    if (existingIdx != -1) {
      await selectChannel(dmId);
      return;
    }

    final dmChannel = BitchatChannel(
      id: dmId,
      name: peer.nickname,
      type: ChannelType.direct,
    );

    _channels.add(dmChannel);
    channelsNotifier.value = List.unmodifiable(_channels);
    await _db.upsertBitchatChannel(dmChannel.toMap());
    await selectChannel(dmId);
  }

  void toggleBleMesh(bool enable) {
    if (enable) {
      BluetoothPermissionService.requestPermissions();
      bleMeshService.start();
    } else {
      bleMeshService.stop();
    }
  }

  Future<bool> checkBluetoothPermissions() => BluetoothPermissionService.checkPermissions();
  Future<bool> requestBluetoothPermissions() => BluetoothPermissionService.requestPermissions();

  Future<void> addCustomRelay(String url) async {
    await nostrRelayService.addRelay(url);
  }

  Future<void> removeCustomRelay(String url) async {
    await nostrRelayService.removeRelay(url);
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(':', '').replaceAll('-', '').trim();
    final list = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      if (i + 2 <= clean.length) {
        list.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
    }
    return Uint8List.fromList(list);
  }

  void dispose() {
    _bleSub?.cancel();
    _nostrSub?.cancel();
    _peerSub?.cancel();
    _unifiedMessageController.close();
    bleMeshService.dispose();
    nostrRelayService.dispose();
    activeChannelNotifier.dispose();
    channelsNotifier.dispose();
    currentChannelMessagesNotifier.dispose();
    currentNicknameNotifier.dispose();
    currentPeerIdNotifier.dispose();
    currentNpubNotifier.dispose();
  }
}
