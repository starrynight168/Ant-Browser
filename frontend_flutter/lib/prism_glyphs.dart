import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart' as prism_icons;

/// Complete vector glyph catalog for Ant Browser, rendered natively by Prism UI's
/// [prism_icons.GlyphIcon] without relying on Material icon fonts.
abstract final class AntGlyphs {
  static const arrowBack = prism_icons.Glyphs.arrowBack;
  static const chevronBack = prism_icons.Glyphs.chevronBack;
  static const chevronForward = prism_icons.Glyphs.chevronForward;
  static const chevronDown = prism_icons.Glyphs.chevronDown;
  static const picker = prism_icons.Glyphs.picker;
  static const close = prism_icons.Glyphs.close;
  static const check = prism_icons.Glyphs.check;
  static const more = prism_icons.Glyphs.more;
  static const dragHandle = prism_icons.Glyphs.dragHandle;
  static const sort = prism_icons.Glyphs.sort;
  static const search = prism_icons.Glyphs.search;
  static const pin = prism_icons.Glyphs.pin;
  static const eye = prism_icons.Glyphs.eye;
  static const eyeOff = prism_icons.Glyphs.eyeOff;
  static const copy = prism_icons.Glyphs.copy;
  static const paste = prism_icons.Glyphs.paste;
  static const selectAll = prism_icons.Glyphs.selectAll;

  static const add = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 5V19 M5 12H19'),
  ]);

  static const arrowForward = prism_icons.Glyph([
    prism_icons.GlyphPath('M5 12H19 M13 6L19 12L13 18'),
  ]);

  static const chevronUp = prism_icons.Glyph([
    prism_icons.GlyphPath('M6 15L12 9L18 15'),
  ]);

  static const play = prism_icons.Glyph([
    prism_icons.GlyphPath('M7 5L19 12L7 19Z'),
  ]);

  static const stop = prism_icons.Glyph([
    prism_icons.GlyphPath('M6 6H18V18H6Z'),
  ]);

  static const restart = prism_icons.Glyph([
    prism_icons.GlyphPath('M20 12A8 8 0 1 1 17.5 6.2 M20 4V9H15'),
  ]);

  static const refresh = prism_icons.Glyph([
    prism_icons.GlyphPath('M20 12A8 8 0 1 1 17.6 6.3 M20 4V9H15'),
  ]);

  static const sync = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M4 12A8 8 0 0 1 17.5 6.2 M18 4V9H13 M20 12A8 8 0 0 1 6.5 17.8 M6 20V15H11',
    ),
  ]);

  static const edit = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 20H8L19 9L15 5L4 16Z M13.5 6.5L17.5 10.5'),
  ]);

  static const delete = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M4 7H20 M9 4H15 M7 7L8 20H16L17 7 M10 11V16 M14 11V16',
    ),
  ]);

  static const deleteSweep = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 7H15 M6 4H12 M5 7L6 19H12L13 7 M16 11H21 M16 15H20 M16 19H19'),
  ]);

  static const restore = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 12A8 8 0 1 0 6.5 6.2 M4 4V9H9 M12 8V12L15 14'),
  ]);

  static const download = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 4V15 M7 11L12 16L17 11 M4 19H20'),
  ]);

  static const upload = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 16V5 M7 9L12 4L17 9 M4 19H20'),
  ]);

  static const folder = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 6H10L12 8H21V19H3Z'),
  ]);

  static const folderSpecial = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 6H10L12 8H21V19H3Z M12 11V16 M9.5 13.5H14.5'),
  ]);

  static const code = prism_icons.Glyph([
    prism_icons.GlyphPath('M8 7L3 12L8 17 M16 7L21 12L16 17 M13.5 5L10.5 19'),
  ]);

  static const dataObject = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M8 5C6 5 6 7 6 9.5C6 11 5 12 4 12C5 12 6 13 6 14.5C6 17 6 19 8 19 M16 5C18 5 18 7 18 9.5C18 11 19 12 20 12C19 12 18 13 18 14.5C18 17 18 19 16 19',
    ),
  ]);

  static const api = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 12H8 M16 12H20 M8 8H16V16H8Z M12 4V8 M12 16V20'),
  ]);

  static const globe = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 2A10 10 0 1 0 12 22A10 10 0 1 0 12 2 M2 12H22 M12 2C7 7 7 17 12 22 M12 2C17 7 17 17 12 22',
    ),
  ]);

  static const hub = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 12L6 6 M12 12L18 6 M12 12L6 18 M12 12L18 18 M12 9A3 3 0 1 0 12 15A3 3 0 1 0 12 9',
    ),
  ]);

  static const cpu = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M6 6H18V18H6Z M9 9H15V15H9Z M2 9H6 M2 15H6 M18 9H22 M18 15H22 M9 2V6 M15 2V6 M9 18V22 M15 18V22',
    ),
  ]);

  static const extension = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M4 5H10V7.5A1.5 1.5 0 1 0 14 7.5V5H20V10H17.5A1.5 1.5 0 1 0 17.5 14H20V20H14V17.5A1.5 1.5 0 1 0 10 17.5V20H4V14H6.5A1.5 1.5 0 1 0 6.5 10H4Z',
    ),
  ]);

  static const bookmark = prism_icons.Glyph([
    prism_icons.GlyphPath('M6 3H18V21L12 17L6 21Z'),
  ]);

  static const tag = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 12L11 4H20V13L12 21Z M15 8H15.2'),
  ]);

  static const settings = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 8A4 4 0 1 0 12 16A4 4 0 1 0 12 8 M12 2V5 M12 19V22 M2 12H5 M19 12H22 M5 5L7 7 M17 17L19 19 M19 5L17 7 M7 17L5 19',
    ),
  ]);

  static const archive = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 4H20V8H4Z M5 8H19V20H5Z M9 12H15'),
  ]);

  static const docs = prism_icons.Glyph([
    prism_icons.GlyphPath('M5 3H19V21H5Z M8 7H16 M8 11H16 M8 15H13'),
  ]);

  static const book = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 5H11A2 2 0 0 1 12 7V19A2 2 0 0 0 10 18H4Z M20 5H13A2 2 0 0 0 12 7V19A2 2 0 0 1 14 18H20Z'),
  ]);

  static const logs = prism_icons.Glyph([
    prism_icons.GlyphPath('M6 3H15L19 7V21H6Z M15 3V7H19 M9 11H16 M9 15H16 M9 18H13'),
  ]);

  static const bell = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M18 10A6 6 0 0 0 6 10C6 16 3 17 3 18H21C21 17 18 16 18 10 M10 21H14',
    ),
  ]);

  static const user = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M12 11A4 4 0 1 0 12 3A4 4 0 1 0 12 11 M4 21C4 17 7.5 15 12 15C16.5 15 20 17 20 21',
    ),
  ]);

  static const bolt = prism_icons.Glyph([
    prism_icons.GlyphPath('M13 2L4 14H11L10 22L20 10H13Z'),
  ]);

  static const speed = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 17A9 9 0 1 1 20 17 M12 14L16 9 M11 14A1 1 0 1 0 13 14A1 1 0 1 0 11 14'),
  ]);

  static const shield = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3L20 6V12C20 16.5 16.5 19.5 12 21C7.5 19.5 4 16.5 4 12V6Z'),
  ]);

  static const health = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3L20 6V12C20 16.5 16.5 19.5 12 21C7.5 19.5 4 16.5 4 12V6Z M12 9V15 M9 12H15'),
  ]);

  static const history = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 12A8 8 0 1 0 6.5 6.2 M4 4V9H9 M12 7V12L15.5 14'),
  ]);

  static const schedule = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3 M12 7V12L15 14'),
  ]);

  static const calendar = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 6H20V20H4Z M4 10H20 M8 3V7 M16 3V7'),
  ]);

  static const link = prism_icons.Glyph([
    prism_icons.GlyphPath(
      'M9 15L15 9 M10 7L12 5A4 4 0 0 1 18 11L16 13 M14 17L12 19A4 4 0 0 1 6 13L8 11',
    ),
  ]);

  static const openInNew = prism_icons.Glyph([
    prism_icons.GlyphPath('M14 4H20V10 M20 4L11 13 M18 14V20H4V6H10'),
  ]);

  static const filterOff = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 5H21L14 13V19L10 21V13Z M4 4L20 20'),
  ]);

  static const viewList = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 7H6 M9 7H20 M4 12H6 M9 12H20 M4 17H6 M9 17H20'),
  ]);

  static const gridView = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 4H10V10H4Z M14 4H20V10H14Z M4 14H10V20H4Z M14 14H20V20H14Z'),
  ]);

  static const warning = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3L21 19H3Z M12 9V13 M12 16V16.5'),
  ]);

  static const error = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3 M12 8V13 M12 16V16.5'),
  ]);

  static const info = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3 M12 11V16 M12 8V8.5'),
  ]);

  static const checkCircle = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3 M8.5 12.5L11 15L15.5 9.5'),
  ]);

  static const doneAll = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 13L7 17L15 8 M9 17L13 17L21 8'),
  ]);

  static const clearAll = prism_icons.Glyph([
    prism_icons.GlyphPath('M5 7H19 M3 12H17 M7 17H21'),
  ]);

  static const tune = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 7H20 M8 5V9 M4 12H20 M15 10V14 M4 17H20 M10 15V19'),
  ]);

  static const cloud = prism_icons.Glyph([
    prism_icons.GlyphPath('M7 18H18A4 4 0 0 0 18 10H17A5 5 0 0 0 7.5 8.5A4 4 0 0 0 7 18Z'),
  ]);

  static const cloudOff = prism_icons.Glyph([
    prism_icons.GlyphPath('M7 18H17 M4 4L20 20 M18 10A4 4 0 0 1 20 16'),
  ]);

  static const cloudUpload = prism_icons.Glyph([
    prism_icons.GlyphPath('M7 18H18A4 4 0 0 0 18 10H17A5 5 0 0 0 7.5 8.5A4 4 0 0 0 7 18Z M12 12V19 M9.5 14.5L12 12L14.5 14.5'),
  ]);

  static const save = prism_icons.Glyph([
    prism_icons.GlyphPath('M5 4H16L20 8V20H5Z M8 4V9H15V4 M8 14H17V20H8Z'),
  ]);

  static const compare = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 9H19 M15 5L19 9L15 13 M20 15H5 M9 11L5 15L9 19'),
  ]);

  static const location = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 21C12 21 18 15 18 10A6 6 0 1 0 6 10C6 15 12 21 12 21Z M12 8A2 2 0 1 0 12 12A2 2 0 1 0 12 8'),
  ]);

  static const locationSearch = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 5A7 7 0 1 0 12 19A7 7 0 1 0 12 5 M12 2V5 M12 19V22 M2 12H5 M19 12H22'),
  ]);

  static const mail = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 6H20V18H4Z M4 7L12 13L20 7'),
  ]);

  static const chat = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 5H20V16H9L4 20Z'),
  ]);

  static const fire = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3C15 7 18 9.5 18 14A6 6 0 1 1 6 14C6 11 8 8.5 10 7C10 9 11 10 12 10C12 7 12 5 12 3Z'),
  ]);

  static const sparkles = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3L14 9L20 11L14 13L12 19L10 13L4 11L10 9Z'),
  ]);

  static const exit = prism_icons.Glyph([
    prism_icons.GlyphPath('M10 4H5V20H10 M14 8L19 12L14 16 M9 12H19'),
  ]);

  static const deselect = prism_icons.Glyph([
    prism_icons.GlyphPath('M5 5H19V19H5Z M4 4L20 20'),
  ]);

  static const arrowUp = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 19V5 M6 11L12 5L18 11'),
  ]);

  static const arrowDown = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 5V19 M6 13L12 19L18 13'),
  ]);

  static const alignBottom = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 4V16 M7 11L12 16L17 11 M5 20H19'),
  ]);

  static const factCheck = prism_icons.Glyph([
    prism_icons.GlyphPath('M4 5H20V19H4Z M7 9H11 M7 13H11 M13.5 12L15.5 14L18.5 10'),
  ]);

  static const removeCircle = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3 M8 12H16'),
  ]);

  static const pending = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3 M8 12H8.2 M12 12H12.2 M16 12H16.2'),
  ]);

  static const circle = prism_icons.Glyph([
    prism_icons.GlyphCircle(12, 12, 5.5, role: prism_icons.GlyphRole.line),
  ]);

  static const circleSolid = prism_icons.Glyph([
    prism_icons.GlyphCircle(12, 12, 5.5, role: prism_icons.GlyphRole.line, solid: true),
  ]);

  static const browser = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 5H21V19H3Z M3 9H21'),
  ]);

  static const browserOff = prism_icons.Glyph([
    prism_icons.GlyphPath('M3 5H21V19H3Z M4 4L20 20'),
  ]);

  static const robot = prism_icons.Glyph([
    prism_icons.GlyphPath('M12 3V6 M6 8H18V17H6Z M9 11H9.2 M15 11H15.2 M9 14H15 M4 10V15 M20 10V15'),
  ]);
}

/// Renders an [AntGlyphs] vector icon via Prism UI's native [prism_icons.GlyphIcon].
class PrismGlyph extends StatelessWidget {
  const PrismGlyph(this.glyph, {super.key, this.size = 18, this.color});

  final prism_icons.Glyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return prism_icons.GlyphIcon(glyph, size: size, color: color);
  }
}
