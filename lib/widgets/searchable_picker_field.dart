import 'package:flutter/material.dart';

import '../data/locations_data.dart';
import '../theme/app_theme.dart';

class SearchablePickerField extends StatelessWidget {
  final String label;
  final String searchHint;
  final LocationOption? value;
  final List<LocationOption> options;
  final bool enabled;
  final ValueChanged<LocationOption> onSelected;

  const SearchablePickerField({
    super.key,
    required this.label,
    required this.searchHint,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return FormField<LocationOption>(
      key: ValueKey('$label:${value?.nameEnglish ?? ''}'),
      initialValue: value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (selection) =>
          selection == null ? '$label is required.' : null,
      builder: (state) {
        final error = state.errorText;
        final borderColor = error == null
            ? WellarTheme.border
            : WellarTheme.danger;
        final selectedName = state.value?.localizedName(isArabic) ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: ValueKey('picker-field-$label'),
                borderRadius: BorderRadius.circular(14),
                onTap: enabled
                    ? () async {
                        final selected = await _showOptions(context, isArabic);
                        if (selected == null) return;
                        state.didChange(selected);
                        onSelected(selected);
                      }
                    : null,
                child: InputDecorator(
                  isEmpty: selectedName.isEmpty,
                  decoration: InputDecoration(
                    labelText: label,
                    errorText: error,
                    enabled: enabled,
                    filled: true,
                    fillColor: enabled
                        ? WellarTheme.surfaceSoft
                        : WellarTheme.surfaceSoft.withValues(alpha: 0.45),
                    contentPadding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      15,
                      12,
                      15,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: WellarTheme.primary),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: WellarTheme.danger),
                    ),
                    suffixIcon: Icon(
                      Icons.expand_more_rounded,
                      color: enabled
                          ? WellarTheme.textMuted
                          : WellarTheme.disabled,
                    ),
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      selectedName.isEmpty ? ' ' : selectedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? WellarTheme.text
                            : WellarTheme.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<LocationOption?> _showOptions(BuildContext context, bool isArabic) {
    return showModalBottomSheet<LocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: WellarTheme.surface,
      builder: (context) => _PickerSheet(
        label: label,
        searchHint: searchHint,
        options: options,
        isArabic: isArabic,
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final String label;
  final String searchHint;
  final List<LocationOption> options;
  final bool isArabic;

  const _PickerSheet({
    required this.label,
    required this.searchHint,
    required this.options,
    required this.isArabic,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.options
        .where((option) {
          final query = _query.trim().toLowerCase();
          if (query.isEmpty) return true;
          return option.nameEnglish.toLowerCase().contains(query) ||
              option.nameArabic.contains(_query.trim());
        })
        .toList(growable: false);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: maxHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.label,
              style: WellarTheme.heading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: WellarTheme.surfaceSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: WellarTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: WellarTheme.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'No matches found',
                        style: WellarTheme.caption,
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: matches.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: WellarTheme.border),
                      itemBuilder: (context, index) {
                        final option = matches[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            option.localizedName(widget.isArabic),
                            textAlign: widget.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
                            style: const TextStyle(color: WellarTheme.text),
                          ),
                          onTap: () => Navigator.pop(context, option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
