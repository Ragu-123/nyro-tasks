import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/bitchat/bitchat_models.dart';
import '../../utils/theme.dart';
import '../../widgets/top_banner_notification.dart';

class BitchatMessageDetailsModal extends StatelessWidget {
  final BitchatMessage message;

  const BitchatMessageDetailsModal({
    Key? key,
    required this.message,
  }) : super(key: key);

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    TopBanner.show(
      context,
      title: 'Copied',
      message: '$label copied.',
      icon: Icons.check_circle_outline,
      color: googleGreen,
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = PeerColors.getColor(message.senderPeerID ?? message.sender);
    final fullTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(message.timestamp);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
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
                CircleAvatar(
                  radius: 18,
                  backgroundColor: avatarColor.withOpacity(0.18),
                  child: Text(
                    message.sender.isNotEmpty ? message.sender[0].toUpperCase() : 'U',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: avatarColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.sender,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                      ),
                      Text(
                        'Message Metadata & Route',
                        style: const TextStyle(fontSize: 11, color: googleTextSecondary),
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
          const Divider(height: 1, thickness: 1, color: googleHairline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoCard(
                  context,
                  title: 'Message ID',
                  value: message.id,
                  copyable: true,
                  icon: Icons.tag,
                ),
                const SizedBox(height: 8),
                _buildInfoCard(
                  context,
                  title: 'Timestamp',
                  value: fullTime,
                  copyable: false,
                  icon: Icons.schedule,
                ),
                const SizedBox(height: 8),
                _buildInfoCard(
                  context,
                  title: 'Channel',
                  value: message.channel ?? 'mesh',
                  copyable: false,
                  icon: Icons.tag,
                ),
                const SizedBox(height: 8),
                _buildInfoCard(
                  context,
                  title: 'Transport Route',
                  value: '${message.transportType.displayName} (Hops: ${message.hopCount}, TTL: 7)',
                  copyable: false,
                  icon: Icons.route_outlined,
                ),
                const SizedBox(height: 8),
                _buildInfoCard(
                  context,
                  title: 'Delivery Status',
                  value: message.deliveryStatus.displayText,
                  copyable: false,
                  icon: Icons.done_all,
                ),
                const SizedBox(height: 8),
                _buildInfoCard(
                  context,
                  title: 'Security & Cryptography',
                  value: message.isPrivate
                      ? 'End-to-End Encrypted (Noise / NIP-44)'
                      : 'Public Broadcast (Ed25519 / BIP-340 Signed)',
                  copyable: false,
                  icon: Icons.shield_outlined,
                ),
                if (message.senderPeerID != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    context,
                    title: 'Sender Peer ID',
                    value: message.senderPeerID!,
                    copyable: true,
                    icon: Icons.bluetooth,
                  ),
                ],
                if (message.senderFingerprint != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    context,
                    title: 'Cryptographic Fingerprint',
                    value: message.senderFingerprint!,
                    copyable: true,
                    icon: Icons.fingerprint,
                  ),
                ],
                const SizedBox(height: 8),
                _buildInfoCard(
                  context,
                  title: 'Payload Statistics',
                  value: '${message.content.length} chars | ${message.imageBase64 != null ? "Image Attached | " : ""}${message.content.length + (message.imageBase64?.length ?? 0) + 32} bytes wire size',
                  copyable: false,
                  icon: Icons.data_usage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String value,
    required bool copyable,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: googleTextPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (copyable)
                InkWell(
                  onTap: () => _copyToClipboard(context, value, title),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy, size: 15, color: googleBlue),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
