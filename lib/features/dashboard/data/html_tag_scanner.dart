import '../../../core/utils/html_unescape.dart';

/// One HTML start tag with its attributes. Written instead of using the
/// `html` package because that is only a *dev* dependency of this project
/// (build-time catalog generator, never imported under `lib/`); promoting it
/// to a runtime dependency would mean editing `pubspec.yaml` just for this
/// phase. A start-tag scanner is enough here: it is independent of attribute
/// order, extra attributes, quoting style (`"`/`'`/unquoted), whitespace and
/// newlines inside a tag — exactly the variations that broke the previous
/// single-line regexes (`dashboard.html:184-185` puts a newline between
/// `href` and `class`).
class HtmlTag {
  const HtmlTag({required this.name, required this.attributes, required this.start, required this.end});

  /// Lower-cased tag name.
  final String name;

  /// Lower-cased attribute names → entity-unescaped values (`''` for a bare
  /// attribute).
  final Map<String, String> attributes;

  /// Index of `<` and the index just after the closing `>`.
  final int start;
  final int end;

  List<String> get classes => (attributes['class'] ?? '').split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();

  bool hasClass(String token) => classes.contains(token);
}

// A start tag: quoted attribute values may contain `>`.
final RegExp _tagPattern = RegExp(r'''<([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''');
final RegExp _attrPattern = RegExp(r'''([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?''');
final RegExp _commentPattern = RegExp(r'<!--[\s\S]*?-->');

/// Removes HTML comments so tags inside them (e.g. the template's own
/// `<!-- ... -->` notes) are never scanned. Run once per document.
String stripHtmlComments(String html) => html.replaceAll(_commentPattern, '');

/// Every start tag in [html], optionally limited to [name], in document order.
Iterable<HtmlTag> scanTags(String html, {String? name}) sync* {
  final wanted = name?.toLowerCase();
  for (final m in _tagPattern.allMatches(html)) {
    final tagName = m.group(1)!.toLowerCase();
    if (wanted != null && tagName != wanted) continue;
    final attributes = <String, String>{};
    for (final a in _attrPattern.allMatches(m.group(2) ?? '')) {
      final key = a.group(1)!.toLowerCase();
      final value = a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
      attributes.putIfAbsent(key, () => unescapeHtmlEntities(value));
    }
    yield HtmlTag(name: tagName, attributes: attributes, start: m.start, end: m.end);
  }
}

/// Tags named [name] carrying the class [token].
Iterable<HtmlTag> scanTagsWithClass(String html, String name, String token) =>
    scanTags(html, name: name).where((t) => t.hasClass(token));

/// Plain text of [html] with tags removed, entities unescaped and all
/// whitespace runs (including newlines) collapsed to single spaces.
String htmlToText(String html) {
  final noTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return unescapeHtmlEntities(noTags).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Text between the end of [tag] and the next closing tag of the same name
/// (or the end of [html]). Suitable for leaf elements such as `<span>`,
/// `<small>` and `<div class="stat-card-value">`.
String innerText(String html, HtmlTag tag) {
  final close = html.indexOf(RegExp('</${tag.name}\\s*>', caseSensitive: false), tag.end);
  return htmlToText(html.substring(tag.end, close == -1 ? html.length : close));
}
