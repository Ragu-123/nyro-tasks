import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/pages/tabs/today_tab.dart';
import 'package:tasks/pages/tabs/timetable_tab.dart';
import 'package:tasks/pages/tabs/revisit_tab.dart';
import 'package:tasks/pages/tabs/quizzes_tab.dart';
import 'package:tasks/pages/tabs/reminders_tab.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/data/database_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _currentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    setState(() {});
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2028, 12, 31),
    );
    if (picked != null) {
      setState(() => _currentDate = picked);
    }
  }

  void _showNewTaskBottomSheet() {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 16,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'New Task',
                  hintStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  border: InputBorder.none,
                ),
              ),
              TextField(
                controller: detailsController,
                decoration: const InputDecoration(
                  hintText: 'Add details',
                  hintStyle: TextStyle(fontSize: 14, color: googleTextSecondary),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final text = titleController.text.trim();
                      if (text.isNotEmpty) {
                        await DatabaseService.instance.addCustomReminder(
                          text,
                          DateTime.now().add(const Duration(hours: 1)),
                        );
                        _onDataChanged();
                      }
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEE, d MMM').format(_currentDate);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text(
              'Tasks',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: googleTextPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: googleTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 16, color: googleTextSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today, color: googleBlue),
            tooltip: 'Jump to Today',
            onPressed: () {
              setState(() => _currentDate = DateTime.now());
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: googleBlue,
          unselectedLabelColor: googleTextSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          indicatorColor: googleBlue,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Timetable'),
            Tab(text: 'Revisit'),
            Tab(text: 'Quizzes'),
            Tab(text: 'Reminders'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TodayTab(currentDate: _currentDate, onDataChanged: _onDataChanged),
          TimetableTab(onDataChanged: _onDataChanged),
          RevisitTab(onDataChanged: _onDataChanged),
          const QuizzesTab(),
          const RemindersTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        elevation: 3.0,
        backgroundColor: Colors.white,
        onPressed: _showNewTaskBottomSheet,
        child: Image.asset('assets/images/plus.png', width: 24, height: 24),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        elevation: 8.0,
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.menu, color: googleTextSecondary),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('NYRO GATE Study App • Offline Local Database Active')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: googleTextSecondary),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
