import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/pages/home/home_page.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications and SQLite database
  await NotificationService.instance.init();
  await DatabaseService.instance.database;

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['google_fonts'], license);
  });

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
