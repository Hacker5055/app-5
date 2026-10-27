// ExifScreen.dart — Tab 1: audit, visualise and strip image fingerprints.

import 'package:flutter/material.dart';

import '../../models/vault_models.dart';
import '../../state/VaultController.dart';
import '../../theme/CyberTheme.dart';
import '../widgets/CyberWidgets.dart';
import '../widgets/GpsMapView.dart';
import '../widgets/MetadataTable.dart';

class ExifScreen extends StatelessWidget {
  const ExifScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final item = controller.activeItem;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1040;
            final left = <Widget>[
              _dropZone(),
              if (controller.items.isNotEmpty) _thumbnails(),
              _gpsCard(item),
            ];
            final right = <Widget>[
              _compareCard(item),
              if (item != null && item.clean != null) _reportCard(item),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 9, child: _column(left)),
                        const SizedBox(width: 18),
                        Expanded(flex: 11, child: _column(right)),
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

  Widget _dropZone() {
    return DropZone(
      title: 'Drop images to audit',
      subtitle: 'JPEG · PNG · BMP · WebP — batch supported, nothing leaves the device',
      icon: Icons.add_photo_alternate_outlined,
      onTap: controller.pickImages,
      actions: <Widget>[
        GhostButton(
          label: 'Select files',
          icon: Icons.folder_open_outlined,
          onPressed: controller.pickImages,
        ),
        GhostButton(
          label: 'Mock photo',
          icon: Icons.auto_awesome_outlined,
          onPressed: () => controller.loadMockPhoto(),
        ),
      ],
    );
  }

  Widget _thumbnails() {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = controller.items[index];
          final active = index == controller.activeIndex;
          return GestureDetector(
            onTap: () => controller.selectItem(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 132,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active ? CyberColors.tealBright : CyberColors.stroke,
                  width: active ? 1.4 : 1,
                ),
                boxShadow: active
                    ? <BoxShadow>[
                        BoxShadow(
                          color: CyberColors.teal.withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Image.memory(item.previewBytes, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                    Container(
                      color: const Color(0xFF0B0D12),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                          Text(
                            item.isCleaned ? 'cleaned' : '${item.tagCount} tags',
                            style: TextStyle(
                              fontFamily: CyberTypography.mono,
                              fontSize: 9,
                              color: item.isCleaned ? CyberColors.tealBright : CyberColors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gpsCard(ScanItem? item) {
    final gps = item?.gps;
    final destroyed = item?.isCleaned ?? false;
    return GlassCard(
      title: 'GPS metadata',
      trailing: CyberChip(
        gps == null ? 'no fix' : destroyed ? 'pin destroyed' : 'located',
        color: gps == null
            ? CyberColors.textMuted
            : destroyed
                ? CyberColors.tealBright
                : CyberColors.amber,
        filled: gps != null,
        icon: Icons.my_location,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GpsMapView(gps: gps, destroyed: destroyed),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  gps == null
                      ? '—'
                      : '${gps.latitude.toStringAsFixed(5)}°, ${gps.longitude.toStringAsFixed(5)}°',
                  style: CyberTypography.data.copyWith(fontSize: 11.5),
                ),
              ),
              TextButton(
                onPressed: gps == null
                    ? null
                    : () => controller.media.copyText(
                          '${gps.latitude.toStringAsFixed(6)}, ${gps.longitude.toStringAsFixed(6)}',
                        ),
                child: const Text('copy', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compareCard(ScanItem? item) {
    final audit = item?.audit;
    final clean = item?.clean;
    return GlassCard(
      title: 'Before vs After',
      trailing: Wrap(
        spacing: 6,
        children: <Widget>[
          CyberChip('${item?.tagCount ?? 0} tags', color: CyberColors.amber, filled: true),
          if (item != null)
            CyberChip(
              '${item.sensitiveCount} sensitive',
              color: CyberColors.rose,
              filled: true,
            ),
          if (clean != null)
            CyberChip('0 remaining', color: CyberColors.tealBright, filled: true),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (audit == null)
            SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'Drop an image to inspect its fingerprint.',
                  style: TextStyle(fontSize: 12.5, color: CyberColors.textDim),
                ),
              ),
            )
          else
            MetadataTable(audit: audit, isCleaned: clean != null),
          const SizedBox(height: 14),
          if (item != null)
            Text(
              '${item.name} · ${item.audit.format} · '
              '${item.audit.width > 0 ? '${item.audit.width}×${item.audit.height} · ' : ''}'
              '${_bytes(item.originalBytes.length)}'
              '${clean != null ? ' → ${_bytes(clean.bytes.length)}' : ''}',
              style: const TextStyle(
                fontFamily: CyberTypography.mono,
                fontSize: 10.5,
                color: CyberColors.textDim,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GhostButton(
                label: 'Batch scrub all',
                icon: Icons.layers_outlined,
                onPressed: controller.items.isEmpty || controller.busy ? null : controller.scrubAll,
              ),
              GhostButton(
                label: 'Share',
                icon: Icons.ios_share,
                onPressed: clean == null ? null : controller.shareCleaned,
              ),
              GhostButton(
                label: 'Export cleaned',
                icon: Icons.download_outlined,
                onPressed: clean == null ? null : controller.saveCleaned,
              ),
              NeonButton(
                label: 'Scrub & strip all meta',
                icon: Icons.auto_fix_high,
                dense: true,
                onPressed: item == null || item.isCleaned || controller.busy
                    ? null
                    : controller.scrubActive,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reportCard(ScanItem item) {
    final lines = controller.reportFor(item);
    final clean = item.clean;
    final verdictClean = clean?.clean ?? false;
    return GlassCard(
      title: 'Scrub report',
      trailing: CyberChip(
        verdictClean ? 'verified clean' : 'needs review',
        color: verdictClean ? CyberColors.tealBright : CyberColors.rose,
        filled: true,
        icon: verdictClean ? Icons.verified_outlined : Icons.warning_amber_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 9),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CyberColors.tealBright,
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: CyberColors.teal.withValues(alpha: 0.8), blurRadius: 8),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontFamily: CyberTypography.mono,
                        fontSize: 11,
                        height: 1.5,
                        color: CyberColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
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
