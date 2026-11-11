import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/bitchat/bitchat_models.dart';
import '../../services/bitchat/bitchat_service.dart';
import '../../utils/theme.dart';
import '../../widgets/top_banner_notification.dart';

class BitchatNetworkManagerModal extends StatefulWidget {
  const BitchatNetworkManagerModal({Key? key}) : super(key: key);

  @override
  _BitchatNetworkManagerModalState createState() => _BitchatNetworkManagerModalState();
}

class _BitchatNetworkManagerModalState extends State<BitchatNetworkManagerModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    TopBanner.show(
      context,
      title: 'Copied',
      message: '$label copied to clipboard.',
      icon: Icons.check_circle_outline,
      color: googleGreen,
    );
  }

  void _showEditNicknameDialog() {
    final controller = TextEditingController(text: BitchatService.instance.nickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: googleSurface,
        title: const Text(
          'Edit Mesh Nickname',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter new nickname',
            hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: googleBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: googleBlue, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: googleTextSecondary, fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                BitchatService.instance.setNickname(newName);
                Navigator.of(ctx).pop();
                setState(() {});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: googleBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Save', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAddRelayDialog() {
    final controller = TextEditingController(text: 'wss://');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: googleSurface,
        title: const Text(
          'Add Nostr Relay',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'wss://relay.example.com',
            hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: googleBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: googleBlue, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: googleTextSecondary, fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.startsWith('wss://') && url.length > 6) {
                BitchatService.instance.addCustomRelay(url);
                Navigator.of(ctx).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: googleBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Add Relay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: googleBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: googleBlueContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.hub_outlined, color: googleBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Network & Mesh Manager',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: googleTextPrimary,
                        ),
                      ),
                      Text(
                        'Bluetooth mesh, Nostr relays, and keys',
                        style: TextStyle(
                          fontSize: 12,
                          color: googleTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: googleTextSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tab Bar
          TabBar(
            controller: _tabController,
            indicatorColor: googleBlue,
            indicatorWeight: 2.5,
            labelColor: googleBlue,
            unselectedLabelColor: googleTextSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
            tabs: const [
              Tab(icon: Icon(Icons.bluetooth, size: 18), text: 'BLE Mesh'),
              Tab(icon: Icon(Icons.dns_outlined, size: 18), text: 'Relays'),
              Tab(icon: Icon(Icons.fingerprint, size: 18), text: 'Identity'),
            ],
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBleMeshTab(),
                _buildRelaysTab(),
                _buildIdentityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 1: BLE Mesh ---
  Widget _buildBleMeshTab() {
    return ValueListenableBuilder<bool>(
      valueListenable: BitchatService.instance.bleMeshActiveNotifier,
      builder: (context, isMeshActive, _) {
        return ValueListenableBuilder<List<BitchatPeer>>(
          valueListenable: BitchatService.instance.peersNotifier,
          builder: (context, peers, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // BLE Mesh Switch Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMeshActive ? googleBlueContainer.withOpacity(0.2) : googleBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMeshActive ? googleBlue.withOpacity(0.3) : googleBorder,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isMeshActive ? googleBlue : googleBorder,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isMeshActive ? Icons.bluetooth : Icons.bluetooth_disabled,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMeshActive ? 'Bluetooth Mesh Active' : 'Bluetooth Mesh Paused',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: googleTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isMeshActive
                                  ? 'Advertising service F47B5E2D & scanning for local peers'
                                  : 'Mesh radio is turned off',
                              style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isMeshActive,
                        activeColor: googleBlue,
                        onChanged: (val) {
                          BitchatService.instance.toggleBleMesh(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Peers Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Nearby Mesh Peers (${peers.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary,
                      ),
                    ),
                    if (isMeshActive)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: googleGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Scanning',
                            style: TextStyle(fontSize: 11, color: googleGreen, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                if (peers.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: googleBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: googleBorder, width: 1),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.bluetooth_searching, color: googleTextSecondary, size: 36),
                        const SizedBox(height: 12),
                        const Text(
                          'No Nearby Peers Discovered',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Nearby devices running BitChat on the same GATT service will appear here automatically.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  )
                else
                  ...peers.map((peer) => _buildPeerTile(peer)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPeerTile(BitchatPeer peer) {
    return Container(
      key: ValueKey('peer_${peer.peerID}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: googleBorder, width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: googleBlueContainer,
            child: Text(
              peer.nickname.isNotEmpty ? peer.nickname[0].toUpperCase() : 'P',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleBlue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      peer.nickname,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: peer.isDirect ? googleBlueContainer.withOpacity(0.5) : googleBackground,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: googleBorder, width: 0.5),
                      ),
                      child: Text(
                        peer.isDirect ? 'Direct' : 'Relayed',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: peer.isDirect ? googleBlue : googleTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${peer.peerID} | Signal: ${peer.rssi ?? -70} dBm',
                  style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              BitchatService.instance.openDirectMessageWithPeer(peer);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: googleBlue,
              side: const BorderSide(color: googleBlue, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // --- Tab 2: Nostr Relays ---
  Widget _buildRelaysTab() {
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: BitchatService.instance.relayStatusNotifier,
      builder: (context, relayStatus, _) {
        final connectedCount = relayStatus.values.where((v) => v).length;
        final totalCount = relayStatus.length;
        final healthMap = BitchatService.instance.nostrRelayService.relayHealth;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status Summary Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: googleBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: googleBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: connectedCount > 0 ? googleGreen.withOpacity(0.15) : googleAmber.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_outlined,
                      color: connectedCount > 0 ? googleGreen : googleAmber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$connectedCount of $totalCount Relays Connected',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'WebSockets handle geohashes, presence, and remote routing',
                          style: TextStyle(fontSize: 11, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Relays Header with Add Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Configured Relays',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                ),
                TextButton.icon(
                  onPressed: _showAddRelayDialog,
                  icon: const Icon(Icons.add, size: 16, color: googleBlue),
                  label: const Text('Add Relay', style: TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            ...relayStatus.entries.map((entry) {
              final url = entry.key;
              final isConnected = entry.value;
              final health = healthMap[url];
              final isDefault = [
                'wss://relay.damus.io',
                'wss://nos.lol',
                'wss://relay.primal.net',
                'wss://offchain.pub',
                'wss://nostr21.com',
              ].contains(url);

              return Container(
                key: ValueKey('relay_$url'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: googleSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: googleBorder, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isConnected ? googleGreen : googleAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            url,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: googleTextPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? 'Connected | Sent: ${health?.messagesSent ?? 0} | Recv: ${health?.messagesReceived ?? 0}'
                                : 'Connecting / Retrying...',
                            style: TextStyle(
                              fontSize: 11,
                              color: isConnected ? googleTextSecondary : googleAmber,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isDefault)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: googleRed),
                        tooltip: 'Remove Relay',
                        onPressed: () {
                          BitchatService.instance.removeCustomRelay(url);
                        },
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // --- Tab 3: Cryptographic Identity ---
  Widget _buildIdentityTab() {
    return ValueListenableBuilder<String>(
      valueListenable: BitchatService.instance.currentNicknameNotifier,
      builder: (context, nickname, _) {
        final peerId = BitchatService.instance.peerId;
        final npub = BitchatService.instance.npub;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: googleBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: googleBorder, width: 1),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: googleBlue,
                    child: Text(
                      nickname.isNotEmpty ? nickname[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Active Mesh Alias',
                          style: TextStyle(fontSize: 11, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showEditNicknameDialog,
                    icon: const Icon(Icons.edit, size: 14, color: googleBlue),
                    label: const Text('Edit', style: TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: googleBlue, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Peer ID Card
            _buildKeyCard(
              title: 'BLE Peer ID (Noise Hash)',
              subtitle: '16 hex characters used for peer discovery & BLE direct routing',
              value: peerId,
              icon: Icons.bluetooth,
            ),
            const SizedBox(height: 12),

            // Nostr npub Card
            _buildKeyCard(
              title: 'Nostr Public Key (npub)',
              subtitle: 'Bech32 identity used for NIP-17 direct messaging over Nostr',
              value: npub,
              icon: Icons.key_outlined,
            ),
            const SizedBox(height: 16),

            // Security note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: googleHairline,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.shield_outlined, size: 16, color: googleTextSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All local mesh messages are signed and direct chats are end-to-end encrypted. Geohash channels derive ephemeral keys deterministically.',
                      style: TextStyle(fontSize: 11, color: googleTextSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeyCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: googleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: googleBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: googleBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: googleBorder, width: 0.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isNotEmpty ? value : 'Generating...',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: googleTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _copyToClipboard(value, title),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.copy, size: 16, color: googleBlue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
