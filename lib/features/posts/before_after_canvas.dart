import 'dart:typed_data';

import 'package:flutter/material.dart';

class BeforeAfterCanvas extends StatelessWidget {
  const BeforeAfterCanvas({
    super.key,
    required this.beforeBytes,
    required this.afterBytes,
    required this.sarpanchName,
    required this.panchayatName,
    required this.sarpanchNameHindi,
    required this.panchayatNameHindi,
    required this.profileImageUrl,
    required this.sealUrl,
    required this.notes,
    this.stacked = false,
    this.frameStyle = 'classic',
    this.generatedArtworkUrl = '',
    this.localizedSarpanchName = '',
    this.localizedPanchayatName = '',
    this.localizedDistrict = '',
    this.localizedState = '',
    this.contentLanguage = 'Hindi',
  });

  final Uint8List? beforeBytes;
  final Uint8List? afterBytes;
  final String sarpanchName;
  final String panchayatName;
  final String sarpanchNameHindi;
  final String panchayatNameHindi;
  final String profileImageUrl;
  final String sealUrl;
  final String notes;
  final bool stacked;
  final String frameStyle;
  final String generatedArtworkUrl;
  final String localizedSarpanchName;
  final String localizedPanchayatName;
  final String localizedDistrict;
  final String localizedState;
  final String contentLanguage;

  // Keep image labels legible over uploaded and generated artwork.
  Widget _photo(Uint8List? bytes, String label) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              Container(
                color: const Color(0xFFE7EDE9),
                child: const Icon(
                  Icons.image_outlined,
                  size: 44,
                  color: Color(0xFF557466),
                ),
              ),
            Positioned(
              left: 8,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frameColor = switch (frameStyle) {
      'celebration' => const Color(0xFF9C3D78),
      'development' => const Color(0xFF176B55),
      'announcement' => const Color(0xFFB34B16),
      'minimal' => const Color(0xFF455A64),
      'tricolor' => const Color(0xFF174A8B),
      _ => const Color(0xFF245C4A),
    };
    const roleLabels = {
      'English': 'Sarpanch',
      'Hindi': 'सरपंच',
      'Marathi': 'सरपंच',
      'Telugu': 'సర్పంచ్',
      'Tamil': 'ஊராட்சி தலைவர்',
      'Gujarati': 'સરપંચ',
    };
    final location = [localizedDistrict, localizedState]
        .where((value) => value.trim().isNotEmpty)
        .join(', ');
    final images = stacked
        ? Column(
            children: [
              _photo(beforeBytes, 'BEFORE'),
              const SizedBox(height: 8),
              _photo(afterBytes, 'AFTER'),
            ],
          )
        : Row(
            children: [
              _photo(beforeBytes, 'BEFORE'),
              const SizedBox(width: 8),
              _photo(afterBytes, 'AFTER'),
            ],
          );
    return Material(
      color: Colors.white,
      child: Container(
        width: 900,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: frameColor, width: frameStyle == 'minimal' ? 2 : 5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance,
                  color: Color(0xFF245C4A),
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    localizedPanchayatName.isNotEmpty
                        ? localizedPanchayatName
                        : (panchayatNameHindi.isNotEmpty
                            ? panchayatNameHindi
                            : panchayatName),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF173E32),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (beforeBytes != null || afterBytes != null)
              SizedBox(height: stacked ? 820 : 430, child: images)
            else
              SizedBox(
                height: 430,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (generatedArtworkUrl.isNotEmpty)
                        Image.network(generatedArtworkUrl, fit: BoxFit.cover)
                      else
                        const ColoredBox(color: Color(0xFFF0F5F1)),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.08),
                              Colors.black.withValues(alpha: 0.68),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 22,
                        child: Text(
                          notes,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 30,
                            height: 1.15,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8)
                            ],
                          ),
                        ),
                      ),
                      if (profileImageUrl.isNotEmpty)
                        Positioned(
                          top: 18,
                          left: 18,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 54,
                              backgroundImage: NetworkImage(profileImageUrl),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            if (frameStyle == 'tricolor')
              const Row(children: [
                Expanded(
                    child: SizedBox(
                        height: 7,
                        child: ColoredBox(color: Color(0xFFFF9933)))),
                Expanded(
                    child: SizedBox(
                        height: 7,
                        child: ColoredBox(color: Color(0xFFFFFFFF)))),
                Expanded(
                    child: SizedBox(
                        height: 7,
                        child: ColoredBox(color: Color(0xFF138808)))),
              ])
            else
              Container(height: 4, color: frameColor),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFE7EDE9),
                  foregroundImage: profileImageUrl.isNotEmpty
                      ? NetworkImage(profileImageUrl)
                      : null,
                  child: profileImageUrl.isEmpty
                      ? const Icon(Icons.person, color: Color(0xFF245C4A))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizedSarpanchName.isNotEmpty
                            ? localizedSarpanchName
                            : (sarpanchNameHindi.isNotEmpty
                                ? sarpanchNameHindi
                                : sarpanchName),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF173E32),
                        ),
                      ),
                      Text(
                        roleLabels[contentLanguage] ?? 'Sarpanch',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF52675D),
                        ),
                      ),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF52675D),
                          ),
                        ),
                    ],
                  ),
                ),
                if (sealUrl.isNotEmpty)
                  Image.network(
                    sealUrl,
                    width: 68,
                    height: 68,
                    fit: BoxFit.contain,
                  )
                else
                  const Icon(
                    Icons.verified_outlined,
                    size: 56,
                    color: Color(0xFF245C4A),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
