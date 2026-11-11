import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      message: '$label copied.',
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
          'Edit Nickname',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter nickname',
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
          'Add Relay',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'wss://relay.damus.io',
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
            child: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.hub_outlined, color: googleBlue, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Network & Mesh',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: googleTextPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: googleTextSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: googleBlue,
            indicatorWeight: 2,
            labelColor: googleBlue,
            unselectedLabelColor: googleTextSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
            tabs: const [
              Tab(icon: Icon(Icons.bluetooth, size: 18), text: 'Bluetooth'),
              Tab(icon: Icon(Icons.dns_outlined, size: 18), text: 'Relays'),
              Tab(icon: Icon(Icons.fingerprint, size: 18), text: 'Identity'),
            ],
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      Icon(
                        isMeshActive ? Icons.bluetooth : Icons.bluetooth_disabled,
                        color: isMeshActive ? googleBlue : googleTextSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isMeshActive ? 'Bluetooth Mesh Active' : 'Bluetooth Mesh Paused',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: googleTextPrimary,
                          ),
                        ),
                      ),
                      Switch(
                        value: isMeshActive,
                        activeColor: googleBlue,
                        onChanged: (val) => BitchatService.instance.toggleBleMesh(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Nearby Peers (${peers.length})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                    ),
                    if (isMeshActive)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: googleGreen, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Scanning',
                            style: TextStyle(fontSize: 11, color: googleGreen, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (peers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: googleBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: googleBorder, width: 1),
                    ),
                    child: Column(
                      children: const [
                        Icon(Icons.bluetooth_searching, color: googleTextSecondary, size: 28),
                        SizedBox(height: 8),
                        Text(
                          'No peers found',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: googleTextPrimary),
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: googleBorder, width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: googleBlueContainer,
            child: Text(
              peer.nickname.isNotEmpty ? peer.nickname[0].toUpperCase() : 'P',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleBlue),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.nickname,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                ),
                Text(
                  'ID: ${peer.peerID} | ${peer.rssi ?? -70} dBm',
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildRelaysTab() {
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: BitchatService.instance.relayStatusNotifier,
      builder: (context, relayStatus, _) {
        final connectedCount = relayStatus.values.where((v) => v).length;
        final totalCount = relayStatus.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Relays ($connectedCount/$totalCount online)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                ),
                TextButton.icon(
                  onPressed: _showAddRelayDialog,
                  icon: const Icon(Icons.add, size: 16, color: googleBlue),
                  label: const Text('Add Relay', style: TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...relayStatus.entries.map((entry) {
              final url = entry.key;
              final isConnected = entry.value;
              final isDefault = [
                'wss://nos.lol',
                'wss://relay.primal.net',
                'wss://nostr.mom',
                'wss://relay.snort.social',
                'wss://offchain.pub',
                'wss://relay.damus.io',
                'wss://nostr21.com',
              ].contains(url);

              return Container(
                key: ValueKey('relay_$url'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: googleSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: googleBorder, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isConnected ? googleGreen : googleAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        url,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: googleTextPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isDefault)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: googleRed),
                        onPressed: () => BitchatService.instance.removeCustomRelay(url),
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

  Widget _buildIdentityTab() {
    return ValueListenableBuilder<String>(
      valueListenable: BitchatService.instance.currentNicknameNotifier,
      builder: (context, nickname, _) {
        final peerId = BitchatService.instance.peerId;
        final npub = BitchatService.instance.npub;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: googleBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: googleBorder, width: 1),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: googleBlue,
                    child: Text(
                      nickname.isNotEmpty ? nickname[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nickname,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showEditNicknameDialog,
                    icon: const Icon(Icons.edit, size: 13, color: googleBlue),
                    label: const Text('Edit', style: TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: googleBlue, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildKeyCard(
              title: 'Peer ID',
              value: peerId,
              icon: Icons.bluetooth,
            ),
            const SizedBox(height: 8),
            _buildKeyCard(
              title: 'Nostr Public Key',
              value: npub,
              icon: Icons.key_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeyCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: googleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: googleBlue),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: googleTextPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _copyToClipboard(value, title),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.copy, size: 15, color: googleBlue),
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
