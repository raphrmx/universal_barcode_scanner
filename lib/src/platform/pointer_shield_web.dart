import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as html;

/// [child] over an empty element that takes the pointer from the camera's
/// frame beneath.
///
/// An iframe keeps every click and every move over it to its own document,
/// so buttons drawn over one would be neither pressed nor hovered. The
/// element sits between the two: the events reach the app, which hands them
/// to [child].
class PointerShield extends StatelessWidget {
  /// Shows [child], reachable by the pointer.
  const PointerShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    // The focus rings stand out of the buttons.
    clipBehavior: Clip.none,
    children: <Widget>[
      Positioned.fill(
        // Nothing to reach with Tab: the keyboard goes to the buttons.
        child: ExcludeFocus(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            onElementCreated: (Object element) {
              (element as html.HTMLElement).style
                ..width = '100%'
                ..height = '100%';
            },
          ),
        ),
      ),
      child,
    ],
  );
}
