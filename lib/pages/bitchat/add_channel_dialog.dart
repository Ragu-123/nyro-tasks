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
  GeohashPrecisionLevel _selectedPrecision = GeohashPrecisionLevel.city;

  @override
  void dispose() {
    _nameController.dispose();
    _geohashController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final rawGeohash = _geohashController.text.trim().isEmpty ? name.toLowerCase() : _geohashController.text.trim().toLowerCase();
    final geohash = _selectedType == ChannelType.geohash ? rawGeohash : null;

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Channel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: googleTextPrimary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Geohash'),
                    selected: _selectedType == ChannelType.geohash,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedType = ChannelType.geohash);
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
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Broadcast'),
                    selected: _selectedType == ChannelType.broadcast,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedType = ChannelType.broadcast);
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
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _selectedType == ChannelType.geohash ? 'Channel Name (e.g. Bangalore)' : 'Channel Name',
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
                const SizedBox(height: 10),
                TextField(
                  controller: _geohashController,
                  decoration: InputDecoration(
                    hintText: 'Geohash tag (e.g. gate2027, tdnu2)',
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
                const SizedBox(height: 12),
                const Text(
                  'Precision Scope',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleTextSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: GeohashPrecisionLevel.values.map((p) {
                    final isSel = _selectedPrecision == p;
                    return ChoiceChip(
                      label: Text(p.label),
                      selected: isSel,
                      onSelected: (val) {
                        if (val) setState(() => _selectedPrecision = p);
                      },
                      selectedColor: googleBlueContainer,
                      labelStyle: TextStyle(
                        fontSize: 10,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? googleBlue : googleTextPrimary,
                      ),
                      side: BorderSide(
                        color: isSel ? googleBlue : googleBorder,
                        width: isSel ? 1.2 : 0.8,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: googleTextSecondary, fontSize: 13)),
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
                    child: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
