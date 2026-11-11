import 'dart:convert';
import 'dart:typed_data';

enum TransportType {
  ble,
  relay,
  both;

  String get displayName {
    switch (this) {
      case TransportType.ble:
        return 'BLE Mesh';
      case TransportType.relay:
        return 'Nostr Relay';
      case TransportType.both:
        return 'BLE & Relay';
    }
  }

  static TransportType fromString(String? val) {
    if (val == null) return TransportType.both;
    switch (val.toLowerCase()) {
      case 'ble':
        return TransportType.ble;
      case 'relay':
        return TransportType.relay;
      case 'both':
      default:
        return TransportType.both;
    }
  }
}

enum DeliveryStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  String get displayText {
    switch (this) {
      case DeliveryStatus.sending:
        return 'Sending...';
      case DeliveryStatus.sent:
        return 'Sent';
      case DeliveryStatus.delivered:
        return 'Delivered';
      case DeliveryStatus.read:
        return 'Read';
      case DeliveryStatus.failed:
        return 'Failed';
    }
  }

  static DeliveryStatus fromString(String? val) {
    if (val == null) return DeliveryStatus.sent;
    switch (val.toLowerCase()) {
      case 'sending':
        return DeliveryStatus.sending;
      case 'sent':
        return DeliveryStatus.sent;
      case 'delivered':
        return DeliveryStatus.delivered;
      case 'read':
        return DeliveryStatus.read;
      case 'failed':
        return DeliveryStatus.failed;
      default:
        return DeliveryStatus.sent;
    }
  }
}

enum ChannelType {
  broadcast,
  geohash,
  direct;

  static ChannelType fromString(String? val) {
    if (val == null) return ChannelType.broadcast;
    switch (val.toLowerCase()) {
      case 'broadcast':
        return ChannelType.broadcast;
      case 'geohash':
        return ChannelType.geohash;
      case 'direct':
        return ChannelType.direct;
      default:
        return ChannelType.broadcast;
    }
  }
}

class BitchatChannel {
  final String id;
  final String name;
  final ChannelType type;
  final String? geohash;
  final int unreadCount;
  final BitchatMessage? lastMessage;
  final int participantCount;

  const BitchatChannel({
    required this.id,
    required this.name,
    required this.type,
    this.geohash,
    this.unreadCount = 0,
    this.lastMessage,
    this.participantCount = 0,
  });

  BitchatChannel copyWith({
    String? id,
    String? name,
    ChannelType? type,
    String? geohash,
    int? unreadCount,
    BitchatMessage? lastMessage,
    int? participantCount,
  }) {
    return BitchatChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      geohash: geohash ?? this.geohash,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      participantCount: participantCount ?? this.participantCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'geohash': geohash,
      'unread_count': unreadCount,
      'participant_count': participantCount,
    };
  }

  factory BitchatChannel.fromMap(Map<String, dynamic> map, {BitchatMessage? lastMessage}) {
    return BitchatChannel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: ChannelType.fromString(map['type'] as String?),
      geohash: map['geohash'] as String?,
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: lastMessage,
      participantCount: (map['participant_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class BitchatMessage {
  final String id;
  final String sender;
  final String? senderPeerID;
  final String? senderNostrPubkey;
  final String? recipientNickname;
  final String content;
  final DateTime timestamp;
  final String? channel;
  final bool isPrivate;
  final bool isRelay;
  final DeliveryStatus deliveryStatus;
  final TransportType transportType;

  const BitchatMessage({
    required this.id,
    required this.sender,
    this.senderPeerID,
    this.senderNostrPubkey,
    this.recipientNickname,
    required this.content,
    required this.timestamp,
    this.channel,
    this.isPrivate = false,
    this.isRelay = false,
    this.deliveryStatus = DeliveryStatus.sent,
    this.transportType = TransportType.both,
  });

  BitchatMessage copyWith({
    String? id,
    String? sender,
    String? senderPeerID,
    String? senderNostrPubkey,
    String? recipientNickname,
    String? content,
    DateTime? timestamp,
    String? channel,
    bool? isPrivate,
    bool? isRelay,
    DeliveryStatus? deliveryStatus,
    TransportType? transportType,
  }) {
    return BitchatMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      senderPeerID: senderPeerID ?? this.senderPeerID,
      senderNostrPubkey: senderNostrPubkey ?? this.senderNostrPubkey,
      recipientNickname: recipientNickname ?? this.recipientNickname,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      channel: channel ?? this.channel,
      isPrivate: isPrivate ?? this.isPrivate,
      isRelay: isRelay ?? this.isRelay,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      transportType: transportType ?? this.transportType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender': sender,
      'sender_peer_id': senderPeerID,
      'sender_nostr_pubkey': senderNostrPubkey,
      'recipient_nickname': recipientNickname,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'channel': channel,
      'is_private': isPrivate ? 1 : 0,
      'is_relay': isRelay ? 1 : 0,
      'delivery_status': deliveryStatus.name,
      'transport_type': transportType.name,
    };
  }

  factory BitchatMessage.fromMap(Map<String, dynamic> map) {
    return BitchatMessage(
      id: map['id'] as String,
      sender: map['sender'] as String,
      senderPeerID: map['sender_peer_id'] as String?,
      senderNostrPubkey: map['sender_nostr_pubkey'] as String?,
      recipientNickname: map['recipient_nickname'] as String?,
      content: map['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num).toInt()),
      channel: map['channel'] as String?,
      isPrivate: (map['is_private'] as int? ?? 0) == 1,
      isRelay: (map['is_relay'] as int? ?? 0) == 1,
      deliveryStatus: DeliveryStatus.fromString(map['delivery_status'] as String?),
      transportType: TransportType.fromString(map['transport_type'] as String?),
    );
  }

  Uint8List toBinaryPayload() {
    final builder = BytesBuilder();

    int flags = 0;
    if (isRelay) flags |= 0x01;
    if (isPrivate) flags |= 0x02;
    if (recipientNickname != null && recipientNickname!.isNotEmpty) flags |= 0x08;
    if (senderPeerID != null && senderPeerID!.isNotEmpty) flags |= 0x10;
    if (channel != null && channel!.isNotEmpty) flags |= 0x40;

    builder.addByte(flags & 0xFF);

    final ts = timestamp.millisecondsSinceEpoch;
    final tsData = ByteData(8);
    tsData.setUint64(0, ts, Endian.big);
    builder.add(tsData.buffer.asUint8List());

    final idBytes = utf8.encode(id);
    final safeIdLen = idBytes.length.clamp(0, 255);
    builder.addByte(safeIdLen);
    builder.add(idBytes.sublist(0, safeIdLen));

    final senderBytes = utf8.encode(sender);
    final safeSenderLen = senderBytes.length.clamp(0, 255);
    builder.addByte(safeSenderLen);
    builder.add(senderBytes.sublist(0, safeSenderLen));

    final contentBytes = utf8.encode(content);
    final safeContentLen = contentBytes.length.clamp(0, 65535);
    final contentLenData = ByteData(2);
    contentLenData.setUint16(0, safeContentLen, Endian.big);
    builder.add(contentLenData.buffer.asUint8List());
    builder.add(contentBytes.sublist(0, safeContentLen));

    if (recipientNickname != null && recipientNickname!.isNotEmpty) {
      final recipBytes = utf8.encode(recipientNickname!);
      final safeRecipLen = recipBytes.length.clamp(0, 255);
      builder.addByte(safeRecipLen);
      builder.add(recipBytes.sublist(0, safeRecipLen));
    }

    if (senderPeerID != null && senderPeerID!.isNotEmpty) {
      final peerBytes = utf8.encode(senderPeerID!);
      final safePeerLen = peerBytes.length.clamp(0, 255);
      builder.addByte(safePeerLen);
      builder.add(peerBytes.sublist(0, safePeerLen));
    }

    if (channel != null && channel!.isNotEmpty) {
      final chBytes = utf8.encode(channel!);
      final safeChLen = chBytes.length.clamp(0, 255);
      builder.addByte(safeChLen);
      builder.add(chBytes.sublist(0, safeChLen));
    }

    return builder.toBytes();
  }

  static String _sanitizeString(String s, {int maxLen = 10000}) {
    if (s.isEmpty) return '';
    final filtered = s
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
        .trim();
    if (filtered.length > maxLen) {
      return filtered.substring(0, maxLen);
    }
    return filtered;
  }

  static BitchatMessage? fromBinaryPayload(Uint8List data) {
    try {
      if (data.length < 13) return null;
      final byteData = ByteData.sublistView(data);
      int offset = 0;

      final flags = byteData.getUint8(offset);
      offset += 1;

      final isRelay = (flags & 0x01) != 0;
      final isPrivate = (flags & 0x02) != 0;
      final hasRecipientNickname = (flags & 0x08) != 0;
      final hasSenderPeerID = (flags & 0x10) != 0;
      final hasChannel = (flags & 0x40) != 0;

      final timestampMillis = byteData.getUint64(offset, Endian.big);
      offset += 8;

      final idLen = byteData.getUint8(offset);
      offset += 1;
      if (idLen > 64 || offset + idLen > data.length) return null;
      final id = _sanitizeString(utf8.decode(data.sublist(offset, offset + idLen)), maxLen: 64);
      offset += idLen;

      final senderLen = byteData.getUint8(offset);
      offset += 1;
      if (senderLen > 64 || offset + senderLen > data.length) return null;
      final sender = _sanitizeString(utf8.decode(data.sublist(offset, offset + senderLen)), maxLen: 64);
      offset += senderLen;

      final contentLen = byteData.getUint16(offset, Endian.big);
      offset += 2;
      if (contentLen > 16384 || offset + contentLen > data.length) return null;
      final content = _sanitizeString(utf8.decode(data.sublist(offset, offset + contentLen)), maxLen: 16384);
      offset += contentLen;

      String? recipientNickname;
      if (hasRecipientNickname && offset < data.length) {
        final rLen = byteData.getUint8(offset);
        offset += 1;
        if (rLen <= 64 && offset + rLen <= data.length) {
          recipientNickname = _sanitizeString(utf8.decode(data.sublist(offset, offset + rLen)), maxLen: 64);
          offset += rLen;
        }
      }

      String? senderPeerID;
      if (hasSenderPeerID && offset < data.length) {
        final pLen = byteData.getUint8(offset);
        offset += 1;
        if (pLen <= 64 && offset + pLen <= data.length) {
          senderPeerID = _sanitizeString(utf8.decode(data.sublist(offset, offset + pLen)), maxLen: 64);
          offset += pLen;
        }
      }

      String? channel;
      if (hasChannel && offset < data.length) {
        final cLen = byteData.getUint8(offset);
        offset += 1;
        if (cLen <= 64 && offset + cLen <= data.length) {
          channel = _sanitizeString(utf8.decode(data.sublist(offset, offset + cLen)), maxLen: 64);
          offset += cLen;
        }
      }

      return BitchatMessage(
        id: id.isNotEmpty ? id : 'msg_${DateTime.now().millisecondsSinceEpoch}',
        sender: sender.isNotEmpty ? sender : 'Peer',
        senderPeerID: senderPeerID,
        recipientNickname: recipientNickname,
        content: content,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMillis),
        channel: channel,
        isPrivate: isPrivate,
        isRelay: isRelay,
        deliveryStatus: DeliveryStatus.delivered,
        transportType: TransportType.ble,
      );
    } catch (_) {
      return null;
    }
  }
}

class BitchatPeer {
  final String peerID;
  final String nickname;
  final Uint8List? noisePublicKey;
  final Uint8List? signingPublicKey;
  final String? nostrPubkey;
  final int? rssi;
  final bool isDirect;
  final bool isConnected;
  final DateTime lastSeen;
  final TransportType transportType;

  BitchatPeer({
    required this.peerID,
    required this.nickname,
    this.noisePublicKey,
    this.signingPublicKey,
    this.nostrPubkey,
    this.rssi,
    this.isDirect = true,
    this.isConnected = false,
    DateTime? lastSeen,
    this.transportType = TransportType.ble,
  }) : lastSeen = lastSeen ?? DateTime.now();

  BitchatPeer copyWith({
    String? peerID,
    String? nickname,
    Uint8List? noisePublicKey,
    Uint8List? signingPublicKey,
    String? nostrPubkey,
    int? rssi,
    bool? isDirect,
    bool? isConnected,
    DateTime? lastSeen,
    TransportType? transportType,
  }) {
    return BitchatPeer(
      peerID: peerID ?? this.peerID,
      nickname: nickname ?? this.nickname,
      noisePublicKey: noisePublicKey ?? this.noisePublicKey,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      nostrPubkey: nostrPubkey ?? this.nostrPubkey,
      rssi: rssi ?? this.rssi,
      isDirect: isDirect ?? this.isDirect,
      isConnected: isConnected ?? this.isConnected,
      lastSeen: lastSeen ?? this.lastSeen,
      transportType: transportType ?? this.transportType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'peer_id': peerID,
      'nickname': nickname,
      'noise_public_key': noisePublicKey != null ? _bytesToHex(noisePublicKey!) : null,
      'signing_public_key': signingPublicKey != null ? _bytesToHex(signingPublicKey!) : null,
      'nostr_pubkey': nostrPubkey,
      'rssi': rssi,
      'is_direct': isDirect ? 1 : 0,
      'is_connected': isConnected ? 1 : 0,
      'last_seen': lastSeen.millisecondsSinceEpoch,
      'transport_type': transportType.name,
    };
  }

  factory BitchatPeer.fromMap(Map<String, dynamic> map) {
    return BitchatPeer(
      peerID: map['peer_id'] as String,
      nickname: map['nickname'] as String,
      noisePublicKey: map['noise_public_key'] != null ? _hexToBytes(map['noise_public_key'] as String) : null,
      signingPublicKey: map['signing_public_key'] != null ? _hexToBytes(map['signing_public_key'] as String) : null,
      nostrPubkey: map['nostr_pubkey'] as String?,
      rssi: (map['rssi'] as num?)?.toInt(),
      isDirect: (map['is_direct'] as int? ?? 1) == 1,
      isConnected: (map['is_connected'] as int? ?? 0) == 1,
      lastSeen: DateTime.fromMillisecondsSinceEpoch((map['last_seen'] as num).toInt()),
      transportType: TransportType.fromString(map['transport_type'] as String?),
    );
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final list = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        list.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return Uint8List.fromList(list);
  }
}

class IdentityAnnouncement {
  final String nickname;
  final Uint8List noisePublicKey;
  final Uint8List signingPublicKey;

  const IdentityAnnouncement({
    required this.nickname,
    required this.noisePublicKey,
    required this.signingPublicKey,
  });

  Uint8List encode() {
    final builder = BytesBuilder();
    final nickBytes = utf8.encode(nickname);

    builder.addByte(0x01);
    builder.addByte(nickBytes.length.clamp(0, 255));
    builder.add(nickBytes);

    builder.addByte(0x02);
    builder.addByte(noisePublicKey.length.clamp(0, 255));
    builder.add(noisePublicKey);

    builder.addByte(0x03);
    builder.addByte(signingPublicKey.length.clamp(0, 255));
    builder.add(signingPublicKey);

    return builder.toBytes();
  }

  static IdentityAnnouncement? decode(Uint8List data) {
    try {
      int offset = 0;
      String? nickname;
      Uint8List? noiseKey;
      Uint8List? signingKey;

      while (offset + 2 <= data.length) {
        final type = data[offset];
        final len = data[offset + 1];
        offset += 2;

        if (offset + len > data.length) break;
        final value = data.sublist(offset, offset + len);
        offset += len;

        if (type == 0x01) {
          nickname = utf8.decode(value);
        } else if (type == 0x02) {
          noiseKey = value;
        } else if (type == 0x03) {
          signingKey = value;
        }
      }

      if (nickname == null || noiseKey == null || signingKey == null) {
        return null;
      }

      if (noiseKey.length != 32 || signingKey.length != 32) {
        return null;
      }

      final safeNick = BitchatMessage._sanitizeString(nickname, maxLen: 40);
      if (safeNick.isEmpty) return null;

      return IdentityAnnouncement(
        nickname: safeNick,
        noisePublicKey: noiseKey,
        signingPublicKey: signingKey,
      );
    } catch (_) {
      return null;
    }
  }
}

class BitchatPacket {
  static const int typeAnnounce = 0x01;
  static const int typeMessage = 0x02;
  static const int typeLeave = 0x03;
  static const int typeNoiseHandshake = 0x10;
  static const int typeNoiseEncrypted = 0x11;
  static const int typeFragment = 0x20;
  static const int typeRequestSync = 0x21;
  static const int typeFileTransfer = 0x22;
  static const int typeVoiceFrame = 0x29;

  static final Uint8List broadcastRecipient = Uint8List(8)..fillRange(0, 8, 0xFF);

  final int version;
  final int type;
  final int ttl;
  final int timestamp;
  final int flags;
  final Uint8List senderID;
  final Uint8List? recipientID;
  final Uint8List payload;
  final Uint8List? signature;

  const BitchatPacket({
    this.version = 1,
    required this.type,
    this.ttl = 7,
    required this.timestamp,
    this.flags = 0,
    required this.senderID,
    this.recipientID,
    required this.payload,
    this.signature,
  });

  Uint8List toBinaryData({bool padding = false}) {
    final builder = BytesBuilder();
    int activeFlags = flags;
    if (recipientID != null) activeFlags |= 0x01;
    if (signature != null) activeFlags |= 0x02;

    builder.addByte(version & 0xFF);
    builder.addByte(type & 0xFF);
    builder.addByte(ttl & 0xFF);

    final tsData = ByteData(8);
    tsData.setUint64(0, timestamp, Endian.big);
    builder.add(tsData.buffer.asUint8List());

    builder.addByte(activeFlags & 0xFF);

    final payloadLenData = ByteData(2);
    payloadLenData.setUint16(0, payload.length.clamp(0, 65535), Endian.big);
    builder.add(payloadLenData.buffer.asUint8List());

    final safeSender = Uint8List(8);
    final copyLen = senderID.length.clamp(0, 8);
    safeSender.setRange(0, copyLen, senderID);
    builder.add(safeSender);

    if (recipientID != null) {
      final safeRecipient = Uint8List(8);
      final rCopyLen = recipientID!.length.clamp(0, 8);
      safeRecipient.setRange(0, rCopyLen, recipientID!);
      builder.add(safeRecipient);
    }

    builder.add(payload);

    if (signature != null) {
      final safeSig = Uint8List(64);
      final sCopyLen = signature!.length.clamp(0, 64);
      safeSig.setRange(0, sCopyLen, signature!);
      builder.add(safeSig);
    }

    final raw = builder.toBytes();
    if (padding && raw.length < 512) {
      final padded = Uint8List(512);
      padded.setRange(0, raw.length, raw);
      return padded;
    }
    return raw;
  }

  static BitchatPacket? fromBinaryData(Uint8List data) {
    try {
      if (data.length < 14 + 8) return null;
      if (data.length > 4096) return null; // Reject oversized packets
      final byteData = ByteData.sublistView(data);
      int offset = 0;

      final version = byteData.getUint8(offset);
      offset += 1;
      if (version != 1) return null;

      final type = byteData.getUint8(offset);
      offset += 1;
      final ttl = byteData.getUint8(offset);
      offset += 1;
      if (ttl < 1 || ttl > 15) return null; // Enforce safe TTL bounds

      final timestamp = byteData.getUint64(offset, Endian.big);
      offset += 8;
      final flags = byteData.getUint8(offset);
      offset += 1;

      final hasRecipient = (flags & 0x01) != 0;
      final hasSignature = (flags & 0x02) != 0;

      final payloadLength = byteData.getUint16(offset, Endian.big);
      offset += 2;
      if (payloadLength > 4096) return null;

      if (offset + 8 > data.length) return null;
      final senderID = data.sublist(offset, offset + 8);
      offset += 8;

      Uint8List? recipientID;
      if (hasRecipient) {
        if (offset + 8 > data.length) return null;
        recipientID = data.sublist(offset, offset + 8);
        offset += 8;
      }

      if (offset + payloadLength > data.length) return null;
      final payload = data.sublist(offset, offset + payloadLength);
      offset += payloadLength;

      Uint8List? signature;
      if (hasSignature) {
        if (offset + 64 <= data.length) {
          signature = data.sublist(offset, offset + 64);
          offset += 64;
        }
      }

      return BitchatPacket(
        version: version,
        type: type,
        ttl: ttl,
        timestamp: timestamp,
        flags: flags,
        senderID: senderID,
        recipientID: recipientID,
        payload: payload,
        signature: signature,
      );
    } catch (_) {
      return null;
    }
  }
}

class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String? sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    this.sig,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String? ?? '',
      pubkey: json['pubkey'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as num?)?.toInt() ?? 1,
      tags: (json['tags'] as List?)
              ?.map((item) => (item as List).map((e) => e.toString()).toList())
              .toList() ??
          [],
      content: json['content'] as String? ?? '',
      sig: json['sig'] as String?,
    );
  }
}
