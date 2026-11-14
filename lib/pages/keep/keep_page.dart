import 'package:flutter/material.dart';
import '../../data/database_service.dart';
import '../../data/keep_note_model.dart';
import '../../utils/theme.dart';
import 'note_editor_sheet.dart';
import 'widgets/keep_empty_state.dart';
import 'widgets/keep_search_bar.dart';
import 'widgets/note_card.dart';

class KeepPage extends StatefulWidget {
  final VoidCallback? onBackToTasks;

  const KeepPage({Key? key, this.onBackToTasks}) : super(key: key);

  @override
  _KeepPageState createState() => _KeepPageState();
}

class _KeepPageState extends State<KeepPage> {
  final TextEditingController _searchController = TextEditingController();

  List<KeepNote> _allNotes = [];
  List<String> _allTags = [];
  bool _isLoading = true;
  bool _isGridView = true;
  bool _showArchived = false;
  String? _selectedTag;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final notes = await DatabaseService.instance.getKeepNotes(
        includeArchived: _showArchived,
        searchQuery: _searchQuery,
        tag: _selectedTag,
      );
      final tags = await DatabaseService.instance.getAllKeepTags();

      if (mounted) {
        setState(() {
          _allNotes = notes;
          _allTags = tags;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Keep notes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openNoteEditor([KeepNote? note]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NoteEditorSheet(
        note: note,
        onSave: (_) => _loadNotes(),
        onDelete: () => _loadNotes(),
      ),
    );
  }

  Future<void> _togglePin(KeepNote note) async {
    await DatabaseService.instance.togglePinKeepNote(note.id, !note.isPinned);
    await _loadNotes();
  }

  Future<void> _toggleArchive(KeepNote note) async {
    await DatabaseService.instance.toggleArchiveKeepNote(note.id, !note.isArchived);
    await _loadNotes();
  }

  Future<void> _deleteNote(KeepNote note) async {
    await DatabaseService.instance.deleteKeepNote(note.id);
    await _loadNotes();
  }

  Future<void> _updateNoteColor(KeepNote note, String colorHex) async {
    final updated = note.copyWith(color: colorHex);
    await DatabaseService.instance.saveKeepNote(updated);
    await _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    final pinnedNotes = _allNotes.where((n) => n.isPinned).toList();
    final otherNotes = _allNotes.where((n) => !n.isPinned).toList();
    final isFiltered = _searchQuery.isNotEmpty || _selectedTag != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          tooltip: 'Back to Tasks',
          onPressed: () {
            if (widget.onBackToTasks != null) {
              widget.onBackToTasks!();
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: googleBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lightbulb_outline_rounded, color: googleBlue, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              _showArchived ? 'Archive Notes' : 'Keep',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: googleTextPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              color: _showArchived ? googleBlue : googleTextSecondary,
            ),
            tooltip: _showArchived ? 'Show Active Notes' : 'Show Archive',
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _loadNotes();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: googleTextSecondary),
            tooltip: 'Reload',
            onPressed: _loadNotes,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Google Keep Floating Pill Search Bar
          KeepSearchBar(
            controller: _searchController,
            onQueryChanged: (query) {
              setState(() => _searchQuery = query);
              _loadNotes();
            },
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
              _loadNotes();
            },
            isGridView: _isGridView,
            onToggleView: () => setState(() => _isGridView = !_isGridView),
            tags: _allTags,
            selectedTag: _selectedTag,
            onSelectTag: (tag) {
              setState(() => _selectedTag = tag);
              _loadNotes();
            },
          ),

          // 2. Notes Stream / List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : _allNotes.isEmpty
                    ? KeepEmptyState(
                        isFiltered: isFiltered,
                        onClearFilter: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _selectedTag = null;
                          });
                          _loadNotes();
                        },
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotes,
                        color: googleBlue,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                          children: [
                            // PINNED SECTION
                            if (pinnedNotes.isNotEmpty) ...[
                              _buildSectionHeader('PINNED', pinnedNotes.length),
                              _buildNotesGridOrList(pinnedNotes),
                              const SizedBox(height: 16),
                            ],

                            // OTHERS SECTION
                            if (pinnedNotes.isNotEmpty && otherNotes.isNotEmpty)
                              _buildSectionHeader('OTHERS', otherNotes.length),

                            if (otherNotes.isNotEmpty)
                              _buildNotesGridOrList(otherNotes),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: googleBlue,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('New Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        onPressed: () => _openNoteEditor(),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        '$title ($count)',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: googleTextSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildNotesGridOrList(List<KeepNote> notes) {
    if (!_isGridView) {
      // 1-Column List View
      return Column(
        children: notes.map((n) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NoteCard(
              note: n,
              onTap: () => _openNoteEditor(n),
              onTogglePin: () => _togglePin(n),
              onToggleArchive: () => _toggleArchive(n),
              onDelete: () => _deleteNote(n),
              onColorChanged: (hex) => _updateNoteColor(n, hex),
            ),
          );
        }).toList(),
      );
    }

    // 2-Column Responsive Staggered Layout
    final leftNotes = <KeepNote>[];
    final rightNotes = <KeepNote>[];

    for (int i = 0; i < notes.length; i++) {
      if (i % 2 == 0) {
        leftNotes.add(notes[i]);
      } else {
        rightNotes.add(notes[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: leftNotes.map((n) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10, right: 4),
                child: NoteCard(
                  note: n,
                  onTap: () => _openNoteEditor(n),
                  onTogglePin: () => _togglePin(n),
                  onToggleArchive: () => _toggleArchive(n),
                  onDelete: () => _deleteNote(n),
                  onColorChanged: (hex) => _updateNoteColor(n, hex),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: Column(
            children: rightNotes.map((n) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 4),
                child: NoteCard(
                  note: n,
                  onTap: () => _openNoteEditor(n),
                  onTogglePin: () => _togglePin(n),
                  onToggleArchive: () => _toggleArchive(n),
                  onDelete: () => _deleteNote(n),
                  onColorChanged: (hex) => _updateNoteColor(n, hex),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
