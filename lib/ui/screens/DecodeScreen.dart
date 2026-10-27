// DecodeScreen.dart — Tab 3: detect, decrypt and export a hidden payload.

import 'package:flutter/material.dart';

import '../../models/vault_models.dart';
import '../../state/VaultController.dart';
import '../../theme/CyberTheme.dart';
import '../widgets/CyberWidgets.dart';

class DecodeScreen extends StatefulWidget {
  const DecodeScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<DecodeScreen> createState() => _DecodeScreenState();
}

class _DecodeScreenState extends State<DecodeScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {});
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final target = controller.decodeTarget;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1040;
            final left = <Widget>[
              DropZone(
                compact: true,
                title: target?.name ?? 'Stego container',
                subtitle: 'PNG carrying an SGV1 LSB payload',
                icon: Icons.shield_outlined,
                onTap: controller.pickContainer,
                actions: <Widget>[
                  GhostButton(
                    label: 'Choose',
                    icon: Icons.folder_outlined,
                    onPressed: controller.pickContainer,
                  ),
                  GhostButton(
                    label: 'Mock container',
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () async {
                      await controller.loadMockContainer();
                      if (controller.lastDemoPassword.isNotEmpty) {
                        _passwordController.text = controller.lastDemoPassword;
                      }
                    },
                  ),
                ],
              ),
              _scanCard(target),
            ];
            final right = <Widget>[
              _revealCard(target),
              if (controller.revealed != null) _outputCard(),
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

  Widget _scanCard(DecodeTarget? target) {
    final header = target?.presence.header;
    final hasContainer = header != null;
    final depth = target?.depth ?? 0;
    return GlassCard(
      title: 'Scan',
      trailing: CyberChip(
        target == null
            ? 'awaiting image'
            : hasContainer
                ? 'SGV1 · $depth-bit · ${_bytes(header!.cipherLen)} ciphertext'
                : 'no container signature',
        color: hasContainer ? CyberColors.tealBright : CyberColors.amber,
        filled: hasContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              color: const Color(0xFF05070A),
              child: target == null
                  ? SizedBox(
                      height: 170,
                      child: Center(
                        child: Text(
                          'No container loaded',
                          style: TextStyle(
                            fontFamily: CyberTypography.mono,
                            fontSize: 11.5,
                            color: CyberColors.textDim,
                          ),
                        ),
                      ),
                    )
                  : Image.memory(target.bytes, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
          if (header != null) ...<Widget>[
            const SizedBox(height: 12),
            const DataRow('Magic header', 'SGV1 (verified)'),
            DataRow('LSB depth', '$depth-bit per channel'),
            DataRow(
              'Payload kind',
              header.isFile ? 'encrypted file' : 'encrypted text',
            ),
            DataRow('Ciphertext', '${header.cipherLen} B + 16 B GCM tag'),
          ],
        ],
      ),
    );
  }

  Widget _revealCard(DecodeTarget? target) {
    final controller = widget.controller;
    final revealed = controller.revealed;
    return GlassCard(
      title: 'Reveal payload',
      trailing: CyberChip(
        revealed != null
            ? 'tag verified'
            : controller.decodeError != null
                ? 'rejected'
                : 'unverified',
        color: revealed != null
            ? CyberColors.tealBright
            : controller.decodeError != null
                ? CyberColors.rose
                : CyberColors.amber,
        filled: revealed != null || controller.decodeError != null,
        icon: revealed != null ? Icons.verified_outlined : Icons.lock_clock,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            onSubmitted: (value) => controller.reveal(value),
            style: const TextStyle(fontFamily: CyberTypography.mono, letterSpacing: 2, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Passphrase',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (controller.decodeError != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: CyberColors.rose.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CyberColors.rose.withValues(alpha: 0.34)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.error_outline, size: 15, color: CyberColors.rose),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.decodeError!,
                      style: const TextStyle(fontSize: 11.5, color: CyberColors.rose),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          NeonButton(
            label: 'Decrypt & verify',
            icon: Icons.key_outlined,
            expand: true,
            onPressed: target == null || controller.busy
                ? null
                : () => controller.reveal(_passwordController.text),
          ),
          const SizedBox(height: 16),
          DataRow('magic', target == null ? '—' : target.hasContainer ? 'SGV1' : 'not found'),
          DataRow('version', revealed == null ? '—' : 'v${revealed.header.version}'),
          DataRow(
            'mode',
            revealed == null ? '—' : '${revealed.depth}-bit · ${revealed.header.isFile ? 'file' : 'text'}',
          ),
          DataRow(
            'salt / iv',
            revealed == null
                ? '—'
                : '${revealed.header.salt.length} B / ${revealed.header.iv.length} B',
          ),
          DataRow(
            'elapsed',
            revealed == null ? '—' : '${revealed.elapsed.inMilliseconds} ms',
            valueColor: CyberColors.tealBright,
          ),
          DataRow('PBKDF2 iterations', '${controller.crypto.iterations}'),
        ],
      ),
    );
  }

  Widget _outputCard() {
    final controller = widget.controller;
    final revealed = controller.revealed!;
    final body = revealed.isFile
        ? '${revealed.file!.name}\n${revealed.file!.mimeType}\n'
            '${_bytes(revealed.file!.bytes.length)} of decrypted bytes\n\n'
            'Binary payload — use Export to save it.'
        : revealed.text;
    return GlassCard(
      title: 'Revealed payload',
      trailing: CyberChip(
        revealed.isFile ? 'file' : 'text',
        color: CyberColors.tealBright,
        filled: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CyberColors.obsidianDeep.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CyberColors.stroke),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                body,
                style: const TextStyle(
                  fontFamily: CyberTypography.mono,
                  fontSize: 11.5,
                  height: 1.65,
                  color: Color(0xFFD7E6E2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GhostButton(label: 'Copy', icon: Icons.copy_all_outlined, onPressed: controller.copyRevealed),
              NeonButton(
                label: revealed.isFile ? 'Export file' : 'Export .txt',
                icon: Icons.download_outlined,
                dense: true,
                onPressed: controller.saveRevealed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
