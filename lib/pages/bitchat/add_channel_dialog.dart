import 'package:flutter/material.dart';
import '../../services/bitchat/bitchat_models.dart';
import '../../services/bitchat/bitchat_service.dart';
import '../../utils/theme.dart';

class AddChannelDialog extends StatefulWidget {
  const AddChannelDialog({Key? key}) : super(key: key);

  @override
  _AddChannelDialogState createState() => _AddChannelDialogState();
}

class _AddChannelDialogState extends State<AddChannelDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _geohashController = TextEditingController();
  ChannelType _selectedType = ChannelType.geohash;

  @override
  void dispose() {
    _nameController.dispose();
    _geohashController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final geohash = _selectedType == ChannelType.geohash
        ? (_geohashController.text.trim().isEmpty ? name.toLowerCase() : _geohashController.text.trim().toLowerCase())
        : null;

    BitchatService.instance.addChannel(
      name,
      _selectedType,
      geohash: geohash,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: googleSurface,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: googleBlueContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_circle_outline, color: googleBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Join or Create Channel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: googleTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Channel Type',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: googleTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Geohash Channel'),
                    selected: _selectedType == ChannelType.geohash,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedType = ChannelType.geohash;
                        });
                      }
                    },
                    selectedColor: googleBlueContainer,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedType == ChannelType.geohash ? googleBlue : googleTextSecondary,
                    ),
                    side: BorderSide(
                      color: _selectedType == ChannelType.geohash ? googleBlue : googleBorder,
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Custom Mesh'),
                    selected: _selectedType == ChannelType.broadcast,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedType = ChannelType.broadcast;
                        });
                      }
                    },
                    selectedColor: googleBlueContainer,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedType == ChannelType.broadcast ? googleBlue : googleTextSecondary,
                    ),
                    side: BorderSide(
                      color: _selectedType == ChannelType.broadcast ? googleBlue : googleBorder,
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _selectedType == ChannelType.geohash ? 'Channel Display Name' : 'Channel Name',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: googleTextSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: _selectedType == ChannelType.geohash ? 'e.g. GATE Bangalore' : 'e.g. Algorithms Study',
                hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: googleBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: googleBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: googleBlue, width: 1.5),
                ),
              ),
            ),
            if (_selectedType == ChannelType.geohash) ...[
              const SizedBox(height: 14),
              const Text(
                'Geohash Tag',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: googleTextSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _geohashController,
                decoration: InputDecoration(
                  hintText: 'e.g. tdnu2, gate2027, blr',
                  hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: googleBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: googleBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: googleBlue, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Geohashes route through Nostr relays with location privacy keys.',
                style: TextStyle(fontSize: 11, color: googleTextSecondary),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: googleTextSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: googleBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Add Channel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
