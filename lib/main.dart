// Exif Cleaner & Stego Vault (منظف البصمات الرقمية والتشفير المخفي)
//
// Offline-only Android application:
//   Tab 1 — audit and strip EXIF / XMP / IPTC / GPS / serial numbers
//   Tab 2 — AES-256-GCM encrypt a payload and hide it in the RGB LSB plane
//   Tab 3 — detect, decrypt and export a hidden payload
//
// The app declares no INTERNET permission, so the security boundary is enforced
// by the operating system, not by convention.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/VaultController.dart';
import 'theme/CyberTheme.dart';
import 'ui/AppShell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: CyberColors.obsidianDeep,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const StegoVaultApp());
}

class StegoVaultApp extends StatefulWidget {
  const StegoVaultApp({super.key});

  @override
  State<StegoVaultApp> createState() => _StegoVaultAppState();
}

class _StegoVaultAppState extends State<StegoVaultApp> {
  late final VaultController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VaultController();
    // Mock Data Mode can be pre-enabled for emulators / screenshots:
    //   flutter run --dart-define=MOCK_DATA=true
    const mockFromEnv = bool.fromEnvironment('MOCK_DATA');
    if (mockFromEnv) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.setMockMode(true));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exif Cleaner & Stego Vault',
      debugShowCheckedModeBanner: false,
      theme: CyberTheme.dark,
      themeMode: ThemeMode.dark,
      home: AppShell(controller: _controller),
      builder: (context, child) {
        // Lock the app to the dark cyber-obsidian palette regardless of the
        // system setting — the design language has no light mode.
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.35,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
