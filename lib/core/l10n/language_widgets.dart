import 'package:flutter/material.dart';

import 'l10n.dart';
import '../widgets/common.dart';
import '../theme/design_tokens.dart';

void showLanguageSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card,
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
                    style: DsStyle.t24w700,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(context, 'languageCount'),
                    style: DsStyle.t14w400.copyWith(color: Colors.grey.shade600),
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
                              isSelected ? AppColors.primaryLight : Colors.transparent,
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? AppColors.primary
                                : AppColors.chip,
                            child: Icon(
                              Icons.language_rounded,
                              color: isSelected ? Colors.white : AppColors.muted,
                            ),
                          ),
                          title: Text(
                            languageInfo[lang]!.nativeName,
                            style: DsStyle.inherit.copyWith(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: AppColors.title),
                          ),
                          subtitle: Text(languageInfo[lang]!.englishName),
                          trailing: isSelected
                              ? Icon(Icons.check_circle_rounded, color: AppColors.primary)
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
