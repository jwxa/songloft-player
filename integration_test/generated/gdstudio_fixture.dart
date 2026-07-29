import 'dart:convert';

const _fixtureBase64 = '';

String get gdstudioFixtureHTML {
  if (_fixtureBase64.isEmpty) {
    throw StateError('请先生成 GDStudio WebView 验收夹具');
  }
  return utf8.decode(base64Decode(_fixtureBase64));
}
