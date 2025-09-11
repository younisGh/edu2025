import 'package:flutter/material.dart';
import 'package:educational_platform/utils/typography.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A reusable row that shows horizontal category tabs and a sort popup button.
/// - If [categories] is provided, it uses that list directly (each item must have 'id' and 'name').
/// - If [categories] is null, it loads categories from Firestore collection 'categories' ordered by 'name'.
class CategoryTabsWithSort extends StatelessWidget {
  final List<Map<String, String>>? categories;
  final String activeTab;
  final ValueChanged<String> onTabSelected;
  final String sortOption;
  final ValueChanged<String> onSortSelected;

  const CategoryTabsWithSort({
    super.key,
    this.categories,
    required this.activeTab,
    required this.onTabSelected,
    required this.sortOption,
    required this.onSortSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (categories == null) {
      // Build with Firestore stream
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('categories')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          final cats = <Map<String, String>>[
            {'id': 'all', 'name': 'الكل'},
            ...((snapshot.data?.docs ?? []).map(
              (d) => {'id': d.id, 'name': (d.data()['name'] ?? '').toString()},
            )),
          ];
          return _buildRow(context, cats);
        },
      );
    }
    // Build with provided categories
    final providedCats = <Map<String, String>>[
      {'id': 'all', 'name': 'الكل'},
      ...categories!,
    ];
    return _buildRow(context, providedCats);
  }

  Widget _buildRow(BuildContext context, List<Map<String, String>> cats) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final isTiny = width < 360;

    if (isMobile) {
      // On mobile: show a dropdown for categories next to the sort button
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: activeTab.isEmpty ? 'all' : activeTab,
              // Keep font sizing via style, color handled by GradientText
              style: TextStyle(fontSize: sf(context, isTiny ? 12 : 14)),
              iconSize: sd(context, isTiny ? 18 : 24),
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: sd(context, isTiny ? 8 : 12),
                  vertical: sd(context, isTiny ? 6 : 10),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(sd(context, isTiny ? 8 : 12)),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(sd(context, isTiny ? 8 : 12)),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              items: cats.map((c) {
                final id = c['id'] ?? 'all';
                final name = c['name'] ?? '';
                return DropdownMenuItem<String>(
                  value: id,
                  child: GradientText(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: sf(context, isTiny ? 12 : 14),
                      fontWeight: FontWeight.w600,
                    ),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                  ),
                );
              }).toList(),
              selectedItemBuilder: (context) {
                return cats.map((c) {
                  final name = c['name'] ?? '';
                  return Align(
                    alignment: Alignment.centerRight,
                    child: GradientText(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: sf(context, isTiny ? 12 : 14),
                        fontWeight: FontWeight.w700,
                      ),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                    ),
                  );
                }).toList();
              },
              onChanged: (val) {
                if (val != null) onTabSelected(val);
              },
            ),
          ),
          SizedBox(width: isTiny ? 8 : 12),
          _SortButton(sortOption: sortOption, onSelected: onSortSelected),
        ],
      );
    }

    // Default (desktop/tablet): horizontal scroll tabs with sort button
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: cats.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final category = entry.value;
                  final isActive = activeTab == category['id'];
                  return AnimatedContainer(
                    key: ValueKey('cat_${category['id']}_$idx'),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => onTabSelected(category['id']!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: isActive
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF667EEA),
                                      Color(0xFF764BA2),
                                    ],
                                  )
                                : null,
                            color: isActive ? null : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: isActive
                                ? Border.all(
                                    color: const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.3),
                                  )
                                : Border.all(color: Colors.grey.shade200),
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xFF6B7280),
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: sf(context, 16),
                            ),
                            child: Text(category['name'] ?? ''),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _SortButton(sortOption: sortOption, onSelected: onSortSelected),
      ],
    );
  }
}

/// Simple gradient text widget using ShaderMask to render a linear gradient
/// over the glyphs. Useful when default widgets don't support gradient color.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final int? maxLines;
  final TextOverflow? overflow;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    required this.gradient,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? const TextStyle();
    return ShaderMask(
      shaderCallback: (bounds) {
        return gradient.createShader(
          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
        );
      },
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        style: baseStyle.copyWith(color: Colors.white),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final String sortOption;
  final ValueChanged<String> onSelected;

  const _SortButton({required this.sortOption, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTiny = width < 360;

    return PopupMenuButton<String>(
      tooltip: 'ترتيب الفيديوهات',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'latest', child: Text('الأحدث')),
        const PopupMenuItem(value: 'oldest', child: Text('الأقدم')),
        const PopupMenuItem(value: 'most_viewed', child: Text('الأكثر مشاهدة')),
        const PopupMenuItem(value: 'least_viewed', child: Text('الأقل مشاهدة')),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: sd(context, isTiny ? 8 : 12),
          vertical: sd(context, isTiny ? 6 : 10),
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
          borderRadius: BorderRadius.circular(sd(context, isTiny ? 8 : 12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_rounded,
              color: Colors.white,
              size: sd(context, isTiny ? 18 : 24),
            ),
            SizedBox(width: sd(context, isTiny ? 4 : 8)),
            Text(
              'ترتيب الفيديوهات',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: sf(context, isTiny ? 12 : 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A responsive GridView wrapper with common spacing and aspect ratio used in dashboards.
class ResponsiveVideoGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double childAspectRatio;

  const ResponsiveVideoGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.childAspectRatio = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTiny = width < 360;
    final isMobile = width < 600;
    // derive effective aspect ratio to avoid overflow on small screens
    double effectiveAspect = childAspectRatio;
    if (isTiny) {
      effectiveAspect = (childAspectRatio - 0.3).clamp(0.7, 2.5);
    } else if (isMobile) {
      effectiveAspect = (childAspectRatio - 0.1).clamp(0.8, 2.5);
    }
    final crossAxisCount = isMobile
        ? 1
        : width > 1200
        ? 4
        : width > 800
        ? 3
        : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
        childAspectRatio: effectiveAspect,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
