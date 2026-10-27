// EncodeScreen.dart — Tab 2: hide an encrypted payload inside a cover image.

import 'package:flutter/material.dart';

import '../../models/vault_models.dart';
import '../../state/VaultController.dart';
import '../../theme/CyberTheme.dart';
import '../widgets/ComparisonSlider.dart';
import '../widgets/CyberWidgets.dart';

class EncodeScreen extends StatefulWidget {
  const EncodeScreen({super.key, required this.controller, this.onOpenDecoder});

  final VaultController controller;

  /// Lets "Test in decoder" switch the shell to Tab 3.
  final VoidCallback? onOpenDecoder;

  @override
  State<EncodeScreen> createState() => _EncodeScreenState();
}

class _EncodeScreenState extends State<EncodeScreen> {
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _payloadController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1040;
            final left = <Widget>[
              _coverDropZone(),
              if (controller.cover != null) _previewCard(),
              _capacityCard(),
            ];
            final right = <Widget>[
              _payloadCard(),
              if (controller.container != null) _resultCard(controller.container!),
            ];
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: _column(left)),
                        const SizedBox(width: 18),
                        Expanded(child: _column(right)),
                      ],
                    )
                  : _column(<Widget>[...left, ...right]),
            );
          },
        );
      },
    );
  }

  Widget _column(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _coverDropZone() {
    return DropZone(
      compact: true,
      title: controller.cover?.name ?? 'Cover image',
      subtitle: 'Lossless PNG output · payload rides the RGB LSB plane',
      icon: Icons.image_outlined,
      onTap: widget.controller.pickCover,
      actions: <Widget>[
        GhostButton(label: 'Choose', icon: Icons.folder_outlined, onPressed: widget.controller.pickCover),
        GhostButton(
          label: 'Mock scene',
          icon: Icons.auto_awesome_outlined,
          onPressed: () => widget.controller.useMockCover(),
        ),
      ],
    );
  }

  Widget _previewCard() {
    final cover = widget.controller.cover!;
    return GlassCard(
      title: 'Container preview',
      trailing: CyberChip('${cover.width}×${cover.height}', color: CyberColors.textMuted),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 260),
          color: const Color(0xFF05070A),
          child: Image.memory(cover.previewBytes, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }

  Widget _capacityCard() {
    final controller = widget.controller;
    final hasCover = controller.cover != null;
    return GlassCard(
      title: 'Capacity calculator',
      trailing: CyberChip(
        hasCover ? '${controller.depth}-bit LSB · ${_bytes(controller.capacityBytes)}' : 'no cover',
        color: controller.payloadFits ? CyberColors.tealBright : CyberColors.rose,
        filled: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CapacityMeter(fraction: controller.utilisation),
          const SizedBox(height: 12),
          DataRow(
            'Max hidden payload',
            hasCover ? '${_bytes(controller.usableBytes)} · ${controller.usableBytes} B' : '—',
            valueColor: CyberColors.tealBright,
          ),
          DataRow(
            'Payload + header + tag',
            '${_bytes(controller.usedBytes)} · ${controller.usedBytes} B',
          ),
          DataRow(
            'Free headroom',
            hasCover ? _bytes((controller.capacityBytes - controller.usedBytes).clamp(0, 1 << 40)) : '—',
          ),
          DataRow('Estimated PSNR', '${controller.estimatedPsnr.toStringAsFixed(1)} dB'),
          const Divider(height: 22),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('2-bit LSB mode', style: TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 2),
                    Text(
                      'Doubles capacity, still visually lossless',
                      style: TextStyle(fontSize: 10.5, color: CyberColors.textDim),
                    ),
                  ],
                ),
              ),
              Switch(
                value: controller.depth == 2,
                onChanged: (value) => controller.setDepth(value ? 2 : 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payloadCard() {
    final controller = widget.controller;
    final strength = _strength(_passwordController.text);
    return GlassCard(
      title: 'Secret payload',
      trailing: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: CyberColors.stroke),
        ),
        child: Row(
          children: <Widget>[
            _kindTab('Text', PayloadKind.text, controller),
            _kindTab('File', PayloadKind.file, controller),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (controller.payloadKind == PayloadKind.text) ...<Widget>[
            TextField(
              controller: _payloadController,
              maxLines: 6,
              minLines: 4,
              onChanged: controller.setPayloadText,
              style: const TextStyle(fontFamily: CyberTypography.mono, fontSize: 12, height: 1.55),
              decoration: const InputDecoration(
                hintText: 'Type the message to hide…',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Text(
                  '${controller.payloadSizeBytes} B',
                  style: const TextStyle(
                    fontFamily: CyberTypography.mono,
                    fontSize: 10.5,
                    color: CyberColors.tealBright,
                  ),
                ),
                const Spacer(),
                const Text(
                  'UTF-8',
                  style: TextStyle(fontFamily: CyberTypography.mono, fontSize: 10, color: CyberColors.textDim),
                ),
              ],
            ),
          ] else ...<Widget>[
            GhostButton(
              label: controller.payloadFile?.name ?? 'Attach file…',
              icon: Icons.attach_file,
              onPressed: controller.pickPayloadFile,
            ),
            if (controller.payloadFile != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: CyberColors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: CyberColors.teal.withValues(alpha: 0.26)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        controller.payloadFile!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: CyberTypography.mono, fontSize: 11),
                      ),
                    ),
                    Text(
                      _bytes(controller.payloadFile!.bytes.length),
                      style: const TextStyle(
                        fontFamily: CyberTypography.mono,
                        fontSize: 10.5,
                        color: CyberColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            onChanged: (value) {
              controller.setPassword(value);
              setState(() {});
            },
            style: const TextStyle(fontFamily: CyberTypography.mono, letterSpacing: 2, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Passphrase',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 9),
          CapacityMeter(fraction: strength.score / 5, height: 4),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text(
                strength.label,
                style: TextStyle(
                  fontFamily: CyberTypography.mono,
                  fontSize: 10.5,
                  color: strength.color,
                ),
              ),
              const Spacer(),
              const Text(
                'PBKDF2-SHA256 · 100k',
                style: TextStyle(fontFamily: CyberTypography.mono, fontSize: 10, color: CyberColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NeonButton(
            label: 'Encrypt & hide in PNG',
            icon: Icons.lock_outline,
            expand: true,
            onPressed: controller.canEmbed ? controller.embed : null,
          ),
          const SizedBox(height: 10),
          Text(
            'Payload is encrypted with AES-256-GCM before a single bit touches the '
            'image. Without the passphrase the ciphertext is indistinguishable from noise.',
            style: TextStyle(fontSize: 10.5, height: 1.55, color: CyberColors.textDim),
          ),
        ],
      ),
    );
  }

  Widget _kindTab(String label, PayloadKind kind, VaultController controller) {
    final active = controller.payloadKind == kind;
    return GestureDetector(
      onTap: () => controller.setPayloadKind(kind),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? CyberColors.teal.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? CyberColors.tealBright : CyberColors.textMuted,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _resultCard(StegoContainer container) {
    final controller = widget.controller;
    return GlassCard(
      title: 'Container ready',
      trailing: CyberChip('SGV1 · ${container.depth}-bit', color: CyberColors.tealBright, filled: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ComparisonSlider(
            coverBytes: controller.cover!.previewBytes,
            stegoBytes: container.previewBytes,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(child: _hud('PSNR', '${container.psnr.toStringAsFixed(1)} dB')),
              const SizedBox(width: 8),
              Expanded(child: _hud('max Δ', '${container.diff.maxChannelDelta}/255')),
              const SizedBox(width: 8),
              Expanded(child: _hud('changed', '${(container.diff.changedRatio * 100).toStringAsFixed(1)}%')),
              const SizedBox(width: 8),
              Expanded(child: _hud('hidden', _bytes(container.payloadBytes))),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GhostButton(
                label: 'Share container',
                icon: Icons.ios_share,
                onPressed: controller.shareContainer,
              ),
              GhostButton(
                label: 'Test in decoder',
                icon: Icons.travel_explore,
                onPressed: () {
                  controller.sendContainerToDecoder();
                  widget.onOpenDecoder?.call();
                },
              ),
              NeonButton(
                label: 'Download PNG',
                icon: Icons.download_outlined,
                dense: true,
                onPressed: controller.saveContainer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hud(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CyberColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label.toUpperCase(), style: CyberTypography.label.copyWith(fontSize: 8.5)),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontFamily: CyberTypography.mono,
              fontSize: 11.5,
              color: CyberColors.tealBright,
            ),
          ),
        ],
      ),
    );
  }

  static _Strength _strength(String password) {
    if (password.isEmpty) {
      return const _Strength(0, 'min. 8 characters recommended', CyberColors.rose);
    }
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 14) score++;
    if (RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    const labels = <String>['too short', 'weak', 'fair', 'good', 'strong', 'vault-grade'];
    const colors = <Color>[
      CyberColors.rose,
      CyberColors.rose,
      CyberColors.amber,
      CyberColors.amber,
      CyberColors.teal,
      CyberColors.tealBright,
    ];
    return _Strength(score, labels[score], colors[score]);
  }

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _Strength {
  const _Strength(this.score, this.label, this.color);
  final int score;
  final String label;
  final Color color;
}
