import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/bitchat/bitchat_models.dart';
import '../../services/bitchat/bitchat_service.dart';
import '../../utils/theme.dart';
import '../../widgets/top_banner_notification.dart';
import 'add_channel_dialog.dart';
import 'bitchat_network_manager_modal.dart';

class BitchatMainPage extends StatefulWidget {
  const BitchatMainPage({Key? key}) : super(key: key);

  @override
  _BitchatMainPageState createState() => _BitchatMainPageState();
}

class _BitchatMainPageState extends State<BitchatMainPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    BitchatService.instance.initialize();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final canSend = _textController.text.trim().isNotEmpty;
    if (canSend != _canSend) {
      setState(() => _canSend = canSend);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    await BitchatService.instance.sendMessage(text);
    _scrollToBottom();
  }

  void _openNetworkManagerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const BitchatNetworkManagerModal(),
    );
  }

  void _openAddChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => const AddChannelDialog(),
    );
  }

  void _showMessageActionSheet(BitchatMessage message) {
    final isMine = message.sender == BitchatService.instance.nickname;

    showModalBottomSheet(
      context: context,
      backgroundColor: googleSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: googleBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.copy, color: googleBlue, size: 18),
                title: const Text('Copy Text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.of(ctx).pop();
                  TopBanner.show(
                    context,
                    title: 'Copied',
                    message: 'Message copied.',
                    icon: Icons.check_circle_outline,
                    color: googleGreen,
                  );
                },
              ),
              if (message.senderPeerID != null && message.senderPeerID!.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.fingerprint, color: googleBlue, size: 18),
                  title: const Text('Copy Peer ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(message.senderPeerID!, style: const TextStyle(fontSize: 10, color: googleTextSecondary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.senderPeerID!));
                    Navigator.of(ctx).pop();
                    TopBanner.show(
                      context,
                      title: 'Copied',
                      message: 'Peer ID copied.',
                      icon: Icons.check_circle_outline,
                      color: googleGreen,
                    );
                  },
                ),
              if (!isMine && message.senderPeerID != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.chat_bubble_outline, color: googleBlue, size: 18),
                  title: Text('Message ${message.sender}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final peer = BitchatPeer(
                      peerID: message.senderPeerID!,
                      nickname: message.sender,
                      lastSeen: message.timestamp,
                    );
                    BitchatService.instance.openDirectMessageWithPeer(peer);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: googleBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: googleSurface,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: googleTextPrimary, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: const [
            Icon(Icons.hub_outlined, color: googleBlue, size: 20),
            SizedBox(width: 8),
            Text(
              'BitChat',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: googleTextPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined, color: googleBlue, size: 22),
            tooltip: 'Network & Relays',
            onPressed: _openNetworkManagerModal,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: googleHairline, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          _buildCompactStatusBar(),
          _buildChannelChips(),
          const Divider(height: 1, thickness: 1, color: googleHairline),
          Expanded(child: _buildMessageList()),
          _buildComposerBar(),
        ],
      ),
    );
  }

  Widget _buildCompactStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: googleSurface,
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: BitchatService.instance.currentNicknameNotifier,
              builder: (context, nickname, _) {
                return InkWell(
                  onTap: _openNetworkManagerModal,
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: googleBlue,
                        child: Text(
                          nickname.isNotEmpty ? nickname[0].toUpperCase() : 'U',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        nickname,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: BitchatService.instance.bleMeshActiveNotifier,
            builder: (context, isMeshActive, _) {
              return ValueListenableBuilder<List<BitchatPeer>>(
                valueListenable: BitchatService.instance.peersNotifier,
                builder: (context, peers, _) {
                  return InkWell(
                    onTap: _openNetworkManagerModal,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isMeshActive ? googleBlueContainer.withOpacity(0.3) : googleBackground,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMeshActive ? googleBlue.withOpacity(0.3) : googleBorder,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMeshActive ? Icons.bluetooth : Icons.bluetooth_disabled,
                            size: 12,
                            color: isMeshActive ? googleBlue : googleTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMeshActive ? '${peers.length} peers' : 'Off',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isMeshActive ? googleBlue : googleTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<Map<String, bool>>(
            valueListenable: BitchatService.instance.relayStatusNotifier,
            builder: (context, relayStatus, _) {
              final connected = relayStatus.values.where((v) => v).length;
              final total = relayStatus.length;

              return InkWell(
                onTap: _openNetworkManagerModal,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: connected > 0 ? googleGreen.withOpacity(0.12) : googleAmber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: connected > 0 ? googleGreen.withOpacity(0.3) : googleAmber.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: connected > 0 ? googleGreen : googleAmber,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$connected/$total',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: connected > 0 ? googleGreen : googleAmber,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChannelChips() {
    return Container(
      height: 44,
      color: googleSurface,
      child: ValueListenableBuilder<List<BitchatChannel>>(
        valueListenable: BitchatService.instance.channelsNotifier,
        builder: (context, channels, _) {
          return ValueListenableBuilder<BitchatChannel?>(
            valueListenable: BitchatService.instance.activeChannelNotifier,
            builder: (context, activeChannel, _) {
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: channels.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == channels.length) {
                    return ActionChip(
                      key: const ValueKey('add_channel_chip'),
                      avatar: const Icon(Icons.add, size: 13, color: googleBlue),
                      label: const Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleBlue)),
                      backgroundColor: googleBackground,
                      side: const BorderSide(color: googleBorder, width: 0.8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onPressed: _openAddChannelDialog,
                    );
                  }

                  final channel = channels[index];
                  final isSelected = activeChannel?.id == channel.id;

                  IconData iconData;
                  if (channel.type == ChannelType.direct) {
                    iconData = Icons.person_outline;
                  } else if (channel.id == 'mesh') {
                    iconData = Icons.bluetooth;
                  } else if (channel.type == ChannelType.geohash) {
                    iconData = Icons.public;
                  } else {
                    iconData = Icons.tag;
                  }

                  return FilterChip(
                    key: ValueKey('channel_chip_${channel.id}'),
                    avatar: Icon(
                      iconData,
                      size: 13,
                      color: isSelected ? googleBlue : googleTextSecondary,
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? googleBlue : googleTextPrimary,
                          ),
                        ),
                        if (channel.unreadCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: const BoxDecoration(color: googleBlue, shape: BoxShape.circle),
                            child: Text(
                              '${channel.unreadCount}',
                              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: googleBlueContainer.withOpacity(0.5),
                    backgroundColor: googleBackground,
                    side: BorderSide(
                      color: isSelected ? googleBlue : googleBorder,
                      width: isSelected ? 1.2 : 0.8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (_) {
                      BitchatService.instance.selectChannel(channel.id);
                      _scrollToBottom();
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return ValueListenableBuilder<List<BitchatMessage>>(
      valueListenable: BitchatService.instance.currentChannelMessagesNotifier,
      builder: (context, messages, _) {
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.chat_bubble_outline_rounded, size: 36, color: googleBlue),
                SizedBox(height: 10),
                Text(
                  'No messages yet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextPrimary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return BitchatMessageBubble(
              key: ValueKey(message.id),
              message: message,
              isMine: message.sender == BitchatService.instance.nickname,
              onLongPress: () => _showMessageActionSheet(message),
            );
          },
        );
      },
    );
  }

  Widget _buildComposerBar() {
    return Container(
      decoration: const BoxDecoration(
        color: googleSurface,
        border: Border(top: BorderSide(color: googleHairline, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        child: ValueListenableBuilder<BitchatChannel?>(
          valueListenable: BitchatService.instance.activeChannelNotifier,
          builder: (context, activeChannel, _) {
            final targetName = activeChannel?.name ?? 'channel';
            return Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: googleBackground,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: googleBorder, width: 1),
                    ),
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 13, color: googleTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Message $targetName...',
                        hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) {
                        if (_canSend) _sendMessage();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _canSend ? googleBlue : googleBorder.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
                    onPressed: _canSend ? _sendMessage : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class BitchatMessageBubble extends StatelessWidget {
  final BitchatMessage message;
  final bool isMine;
  final VoidCallback onLongPress;

  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  const BitchatMessageBubble({
    Key? key,
    required this.message,
    required this.isMine,
    required this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final timeStr = _timeFormatter.format(message.timestamp);

    return InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              CircleAvatar(
                radius: 13,
                backgroundColor: googleBlueContainer,
                child: Text(
                  message.sender.isNotEmpty ? message.sender[0].toUpperCase() : 'U',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleBlue),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMine ? const Color(0xFFE8F0FE) : googleSurface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: isMine ? const Radius.circular(12) : const Radius.circular(2),
                    bottomRight: isMine ? const Radius.circular(2) : const Radius.circular(12),
                  ),
                  border: Border.all(
                    color: isMine ? const Color(0xFFD3E3FD) : googleBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isMine)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.sender,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleBlue),
                          ),
                          if (message.senderPeerID != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${message.senderPeerID!.length >= 6 ? message.senderPeerID!.substring(0, 6) : message.senderPeerID})',
                              style: const TextStyle(fontSize: 9, color: googleTextSecondary, fontFamily: 'monospace'),
                            ),
                          ],
                        ],
                      ),
                    if (!isMine) const SizedBox(height: 2),
                    SelectableText(
                      message.content,
                      style: const TextStyle(fontSize: 13, color: googleTextPrimary, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTransportBadge(message.transportType),
                        const SizedBox(width: 5),
                        Text(timeStr, style: const TextStyle(fontSize: 9, color: googleTextSecondary)),
                        if (isMine) ...[
                          const SizedBox(width: 3),
                          _buildDeliveryStatusIcon(message.deliveryStatus),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportBadge(TransportType type) {
    IconData icon;
    String label;
    Color color;

    switch (type) {
      case TransportType.ble:
        icon = Icons.bluetooth;
        label = 'BLE';
        color = Colors.indigo;
        break;
      case TransportType.relay:
        icon = Icons.cloud_outlined;
        label = 'Relay';
        color = Colors.teal;
        break;
      case TransportType.both:
        icon = Icons.hub_outlined;
        label = 'Mesh';
        color = googleBlue;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusIcon(DeliveryStatus status) {
    switch (status) {
      case DeliveryStatus.sending:
        return const Icon(Icons.access_time, size: 10, color: googleTextSecondary);
      case DeliveryStatus.sent:
        return const Icon(Icons.check, size: 10, color: googleTextSecondary);
      case DeliveryStatus.delivered:
      case DeliveryStatus.read:
        return const Icon(Icons.done_all, size: 10, color: googleBlue);
      case DeliveryStatus.failed:
        return const Icon(Icons.error_outline, size: 10, color: googleRed);
    }
  }
}
