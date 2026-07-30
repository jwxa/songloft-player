import 'package:web/web.dart' as web;

bool _styleInjected = false;

/// Toggle pointer-events on the Flutter semantics host element.
///
/// When [block] is true, injects a CSS rule that forces
/// `pointer-events: none !important` on `flt-semantics-host` and all its
/// descendants. This overrides the engine's inline `pointer-events: auto/all`
/// on individual `flt-semantics` nodes, ensuring they cannot intercept clicks
/// meant for the plugin iframe below.
///
/// The CSS `!important` is necessary because the engine sets inline styles
/// (`element.style.setProperty('pointer-events', 'auto')`) on each semantics
/// node, which would otherwise take precedence over inherited values.
void overrideSemanticsPointerEvents(bool block) {
  if (!_styleInjected) {
    _styleInjected = true;
    final style = web.document.createElement('style') as web.HTMLStyleElement;
    style.textContent =
        'flt-semantics-host.sl-plugin-active,'
        'flt-semantics-host.sl-plugin-active *'
        '{pointer-events:none !important}';
    web.document.head?.append(style);
  }
  final host = web.document.querySelector('flt-semantics-host');
  if (host == null) return;
  if (block) {
    host.classList.add('sl-plugin-active');
  } else {
    host.classList.remove('sl-plugin-active');
  }
}
