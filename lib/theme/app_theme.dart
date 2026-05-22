import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color deepSeaBlue = Color(0xFF1E3A8A);
  static const Color aegeanTurquoise = Color(0xFF06B6D4);
  static const Color sunsetOrange = Color(0xFFFF5722);
  static const Color offWhite = Color(0xFFF8F9FA);
  static const Color darkText = Color(0xFF1A1A2E);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: deepSeaBlue,
          primary: deepSeaBlue,
          secondary: aegeanTurquoise,
          surface: offWhite,
        ),
        scaffoldBackgroundColor: offWhite,
        textTheme: GoogleFonts.poppinsTextTheme(),
        appBarTheme: AppBarTheme(
          backgroundColor: deepSeaBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: aegeanTurquoise,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
