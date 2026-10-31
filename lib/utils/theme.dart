import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

const googleBlue = Color(0xFF0B57D0);
const googleBlueContainer = Color(0xFFD3E3FD);
const googleOnBlueContainer = Color(0xFF041E49);
const googleSurface = Colors.white;
const googleBackground = Color(0xFFF8FAFD);
const googleTextPrimary = Color(0xFF1F1F1F);
const googleTextSecondary = Color(0xFF5F6368);
const googleBorder = Color(0xFFE0E2EC);
const googleHairline = Color(0xFFF1F3F4);
const severityHigh = Color(0xFFB3261E);
const severityMed = Color(0xFFE37400);
const severityLow = Color(0xFF0B57D0);
const googleAmber = Color(0xFFF29900);
const googleGreen = Color(0xFF137333);

final lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: googleBlue,
    onPrimary: Colors.white,
    primaryContainer: googleBlueContainer,
    onPrimaryContainer: googleOnBlueContainer,
    surface: googleSurface,
    onSurface: googleTextPrimary,
    outline: Color(0xFF747775),
    outlineVariant: googleBorder,
  ),
  scaffoldBackgroundColor: googleBackground,
  cardColor: googleSurface,
  dividerColor: googleBorder,
  appBarTheme: const AppBarTheme(
    backgroundColor: googleSurface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: googleTextPrimary),
    titleTextStyle: TextStyle(
      color: googleTextPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: googleSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
    ),
  ),
  textTheme: GoogleFonts.robotoTextTheme().apply(
    bodyColor: googleTextPrimary,
    displayColor: googleTextPrimary,
  ),
);

const systemUiOverlayStyleLight = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarDividerColor: Colors.transparent,
);
