// AppShell.dart — responsive chrome: side rail on tablets, bottom tabs on phones.

import 'package:flutter/material.dart';

import '../state/VaultController.dart';
import '../theme/CyberTheme.dart';
import 'screens/DecodeScreen.dart';
import 'screens/EncodeScreen.dart';
import 'screens/ExifScreen.dart';
import 'widgets/CyberWidgets.dart';

class _TabSpec {
  const _TabSpec(this.index, this.title, this.subtitle, this.icon);
  final String index;
  final String title;
  final String subtitle;
  final IconData icon;
}

const List<_TabSpec> _tabs = <_TabSpec>[
  _TabSpec('01', 'Exif Scrub & Share', 'Strip GPS · XMP · serials', Icons.fingerprint),
  _TabSpec('02', 'Stego Encoder', 'Hide payload in LSB', Icons.lock_outline),
  _TabSpec('03', 'Stego Decoder', 'Reveal · verify · export', Icons.travel_explore),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final VaultController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _go(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return CyberBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final screens = <Widget>[
                    ExifScreen(controller: controller),
                    EncodeScreen(controller: controller, onOpenDecoder: () => _go(2)),
                    DecodeScreen(controller: controller),
                  ];

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _rail(controller),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              _header(controller),
                              if (controller.busy)
                                const LinearProgressIndicator(minHeight: 2, color: CyberColors.teal),
                              Expanded(child: IndexedStack(index: _index, children: screens)),
                              _statusBar(controller),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: <Widget>[
                      _compactHeader(controller),
                      if (controller.busy)
                        const LinearProgressIndicator(minHeight: 2, color: CyberColors.teal),
                      Expanded(child: IndexedStack(index: _index, children: screens)),
                      _statusBar(controller),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------- rail
  Widget _rail(VaultController controller) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x14FFFFFF), Color(0x05FFFFFF)],
        ),
        border: Border(right: BorderSide(color: CyberColors.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const RadialGradient(
                    colors: <Color>[Color(0x382DD4BF), Color(0x0D14B8A6)],
                  ),
                  border: Border.all(color: CyberColors.teal.withValues(alpha: 0.32)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: CyberColors.teal.withValues(alpha: 0.30),
                      blurRadius: 22,
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_moon_outlined, color: CyberColors.tealBright, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'EXIF CLEANER',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                    ),
                    Text(
                      '& STEGO VAULT',
                      style: TextStyle(fontSize: 10.5, letterSpacing: 2.2, color: CyberColors.tealBright),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'منظف البصمات الرقمية والتشفير المخفي',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 10.5, color: CyberColors.textDim, height: 1.6),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < _tabs.length; i++) ...<Widget>[
            _railTile(_tabs[i], i),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          _mockToggle(controller),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: CyberColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CyberColors.amber.withValues(alpha: 0.24)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CyberColors.amber,
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: CyberColors.amber.withValues(alpha: 0.9), blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Air-gapped',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: CyberColors.amberSoft),
                      ),
                      Text(
                        'No INTERNET permission · zero network calls',
                        style: TextStyle(fontSize: 9.5, color: Color(0xB8F59E0B), height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _railTile(_TabSpec tab, int index) {
    final active = _index == index;
    return GestureDetector(
      onTap: () => _go(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: active
              ? LinearGradient(
                  colors: <Color>[
                    CyberColors.teal.withValues(alpha: 0.16),
                    CyberColors.teal.withValues(alpha: 0.03),
                  ],
                )
              : null,
          border: Border.all(
            color: active ? CyberColors.teal.withValues(alpha: 0.34) : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Text(
                tab.index,
                style: TextStyle(
                  fontFamily: CyberTypography.mono,
                  fontSize: 10.5,
                  color: active ? CyberColors.tealBright : CyberColors.textDim,
                ),
              ),
            ),
            Icon(tab.icon, size: 18, color: active ? CyberColors.tealBright : CyberColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tab.title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? CyberColors.text : CyberColors.textMuted,
                    ),
                  ),
                  Text(
                    tab.subtitle,
                    style: const TextStyle(fontSize: 10, color: CyberColors.textDim),
                  ),
                ],
              ),
            ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? CyberColors.tealBright : Colors.white.withValues(alpha: 0.12),
                boxShadow: active
                    ? <BoxShadow>[
                        BoxShadow(color: CyberColors.teal.withValues(alpha: 0.9), blurRadius: 10),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mockToggle(VaultController controller) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Mock Data Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                'Generate synthetic photos & EXIF',
                style: TextStyle(fontSize: 10.5, color: CyberColors.textDim),
              ),
            ],
          ),
        ),
        Switch(
          value: controller.mockMode,
          onChanged: (value) => controller.setMockMode(value),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- header
  Widget _header(VaultController controller) {
    final tab = _tabs[_index];
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CyberColors.stroke)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: CyberColors.teal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: CyberColors.teal.withValues(alpha: 0.3)),
            ),
            child: Text(
              tab.index,
              style: const TextStyle(
                fontFamily: CyberTypography.mono,
                fontSize: 11,
                letterSpacing: 0.8,
                color: CyberColors.tealBright,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(tab.title, style: CyberTypography.title),
          const Spacer(),
          Wrap(
            spacing: 7,
            children: <Widget>[
              const CyberChip('AES-256-GCM', color: CyberColors.tealBright, filled: true),
              const CyberChip('PBKDF2 · 100 000'),
              CyberChip(
                controller.mockMode ? 'MOCK DATA' : 'ON-DEVICE',
                color: controller.mockMode ? CyberColors.amber : CyberColors.textMuted,
                filled: controller.mockMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactHeader(VaultController controller) {
    final tab = _tabs[_index];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CyberColors.stroke)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.shield_moon_outlined, color: CyberColors.tealBright, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(tab.title, style: CyberTypography.title.copyWith(fontSize: 15)),
                    Text(
                      controller.mockMode ? 'mock data mode' : 'on-device · offline',
                      style: const TextStyle(fontSize: 10, color: CyberColors.textDim),
                    ),
                  ],
                ),
              ),
              Switch(
                value: controller.mockMode,
                onChanged: (value) => controller.setMockMode(value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (var i = 0; i < _tabs.length; i++) ...<Widget>[
                  GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _index == i
                            ? CyberColors.teal.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _index == i
                              ? CyberColors.teal.withValues(alpha: 0.34)
                              : CyberColors.stroke,
                        ),
                      ),
                      child: Text(
                        '${_tabs[i].index} ${_tabs[i].title}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _index == i ? CyberColors.tealBright : CyberColors.textMuted,
                          fontWeight: _index == i ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- status bar
  Widget _statusBar(VaultController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0x8C06080C),
        border: Border(top: BorderSide(color: CyberColors.stroke)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: controller.busy ? CyberColors.amber : CyberColors.tealBright,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: (controller.busy ? CyberColors.amber : CyberColors.teal).withValues(alpha: 0.9),
                  blurRadius: 9,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              controller.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: CyberTypography.mono,
                fontSize: 10.5,
                color: CyberColors.textDim,
              ),
            ),
          ),
          if (controller.busy)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: CyberColors.amber),
              ),
            ),
          const Text(
            'ARM64 · release · offline',
            style: TextStyle(
              fontFamily: CyberTypography.mono,
              fontSize: 10,
              color: CyberColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
