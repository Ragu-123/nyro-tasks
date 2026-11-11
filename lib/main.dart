import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/pages/home/home_page.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Defensive pre-launch initialization so app NEVER hangs on splash screen
  try {
    await DatabaseService.instance.database;
  } catch (e) {
    debugPrint('Database initialization error: $e');
  }

  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Notification service initialization error: $e');
  }

  try {
    LicenseRegistry.addLicense(() async* {
      final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
      yield LicenseEntryWithLineBreaks(['google_fonts'], license);
    });
  } catch (_) {}

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiOverlayStyleLight,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NYRO Tasks',
        theme: lightTheme,
        home: const HomePage(),
      ),
    );
  }
}
