import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> enterWebFullscreen() async {
  final el = web.document.documentElement;
  if (el != null) {
    try {
      await el.requestFullscreen().toDart;
    } catch (_) {}
  }
  try {
    await web.window.screen.orientation.lock('landscape').toDart;
  } catch (_) {}
}

Future<void> exitWebFullscreen() async {
  if (web.document.fullscreenElement != null) {
    try {
      await web.document.exitFullscreen().toDart;
    } catch (_) {}
  }
  try {
    web.window.screen.orientation.unlock();
  } catch (_) {}
}

void Function() onWebFullscreenExit(void Function() callback) {
  final listener =
      (web.Event _) {
        if (web.document.fullscreenElement == null) callback();
      }.toJS;
  web.document.addEventListener('fullscreenchange', listener);
  return () => web.document.removeEventListener('fullscreenchange', listener);
}
