// MetadataTable.dart
//
// "Before vs After" comparison table. Each row is a tag that existed in the
// original file; after a scrub the value is struck through and replaced with a
// STRIPPED marker, while colour markers (JFIF/ICC) are shown as kept.

import 'package:flutter/material.dart';

import '../../core/ExifCleanerService.dart';
import '../../core/JpegMeta.dart';
import '../../theme/CyberTheme.dart';

class MetadataTable extends StatelessWidget {
  const MetadataTable({
    super.key,
    required this.audit,
    required this.isCleaned,
    this.maxHeight = 380,
  });

  final MediaAudit audit;
  final bool isCleaned;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (audit.entries.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No EXIF, XMP, IPTC or comment metadata found — this file is already fingerprint-free.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: CyberColors.textDim),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: CyberColors.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Container(
              color: const Color(0xF00B0D12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: <Widget>[
                  Expanded(flex: 4, child: Text('FIELD', style: CyberTypography.label)),
                  Expanded(flex: 5, child: Text('BEFORE', style: CyberTypography.label)),
                  SizedBox(width: 92, child: Text('AFTER', style: CyberTypography.label)),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: audit.entries.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.035),
                  ),
                  itemBuilder: (context, index) {
                    final entry = audit.entries[index];
                    return _MetaRow(entry: entry, isCleaned: isCleaned);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.entry, required this.isCleaned});

  final MetadataEntry entry;
  final bool isCleaned;

  @override
  Widget build(BuildContext context) {
    final color = CyberColors.forGroup(entry.group);
    final harmless = ExifCleanerService.harmlessGroups.contains(entry.group);
    final stripped = isCleaned && !harmless;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withValues(alpha: 0.32)),
                  ),
                  child: Text(
                    entry.group.toUpperCase(),
                    style: TextStyle(
                      fontFamily: CyberTypography.mono,
                      fontSize: 8,
                      letterSpacing: 0.4,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.tag,
                    style: const TextStyle(
                      fontFamily: CyberTypography.mono,
                      fontSize: 10.5,
                      height: 1.35,
                      color: Color(0xFFDCE5EE),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              entry.value,
              style: CyberTypography.data.copyWith(
                color: stripped ? CyberColors.textDim : CyberTypography.data.color,
                decoration: stripped ? TextDecoration.lineThrough : null,
                decorationColor: CyberColors.rose.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: !isCleaned
                ? Text('—', style: CyberTypography.data.copyWith(color: CyberColors.textDim))
                : harmless
                    ? const _AfterTag('KEPT', CyberColors.tealBright)
                    : const _AfterTag('STRIPPED', CyberColors.rose),
          ),
        ],
      ),
    );
  }
}

class _AfterTag extends StatelessWidget {
  const _AfterTag(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: CyberTypography.mono,
          fontSize: 8.5,
          letterSpacing: 0.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
