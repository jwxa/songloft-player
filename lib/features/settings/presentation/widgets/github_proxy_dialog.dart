import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/github_proxy.dart';

/// GitHub 加速代理选择弹窗：预设常用镜像 + 自定义地址，返回选定的代理前缀（空串表示直连）。
class GithubProxyDialog extends StatefulWidget {
  final String current;

  const GithubProxyDialog({super.key, required this.current});

  @override
  State<GithubProxyDialog> createState() => _GithubProxyDialogState();
}

class _GithubProxyDialogState extends State<GithubProxyDialog> {
  late int _selected;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    const presets = kGithubProxyPresets;
    final idx = presets.indexWhere((p) => p.value == widget.current);
    // 命中预设则选中，否则视为自定义（-1）
    _selected = idx >= 0 ? idx : -1;
    _customController = TextEditingController(
      text: idx >= 0 ? '' : widget.current,
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    const presets = kGithubProxyPresets;

    return AlertDialog(
      title: Text(l10n.settingsGithubProxyTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.settingsGithubProxyDialogDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _selected,
              onChanged: (v) {
                if (v != null) setState(() => _selected = v);
              },
              child: Column(
                children: [
                  ...List.generate(presets.length, (i) {
                    return RadioListTile<int>(
                      title: Text(
                        presets[i].value.isEmpty
                            ? l10n.githubProxyDirect
                            : presets[i].label,
                        style: theme.textTheme.bodyMedium,
                      ),
                      value: i,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                  RadioListTile<int>(
                    title: Text(
                      l10n.settingsGithubProxyCustom,
                      style: theme.textTheme.bodyMedium,
                    ),
                    value: -1,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (_selected == -1)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: TextField(
                  controller: _customController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'https://your-proxy.com/',
                    helperText: l10n.settingsGithubProxyCustomHelper,
                    helperMaxLines: 2,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final value =
                _selected == -1
                    ? _customController.text.trim()
                    : presets[_selected].value;
            Navigator.pop(context, value);
          },
          child: Text(l10n.settingsSave),
        ),
      ],
    );
  }
}
