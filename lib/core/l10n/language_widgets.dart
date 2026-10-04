import 'package:flutter/material.dart';

import 'l10n.dart';

void showLanguageSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: ValueListenableBuilder<AppLanguage>(
            valueListenable: languageNotifier,
            builder: (context, selected, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(context, 'language'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(context, 'languageCount'),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: AppLanguage.values.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final lang = AppLanguage.values[index];
                        final isSelected = lang == selected;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor:
                              isSelected ? const Color(0xFFE8F1FF) : Colors.transparent,
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? const Color(0xFF1565C0)
                                : const Color(0xFFF2F4F7),
                            child: Icon(
                              Icons.language_rounded,
                              color: isSelected ? Colors.white : const Color(0xFF667085),
                            ),
                          ),
                          title: Text(
                            languageInfo[lang]!.nativeName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          subtitle: Text(languageInfo[lang]!.englishName),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1565C0))
                              : null,
                          onTap: () {
                            setAppLanguage(lang);
                            Navigator.of(sheetContext).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr(context, 'language'),
      onPressed: () => showLanguageSelector(context),
      icon: const Icon(Icons.language_rounded),
    );
  }
}
