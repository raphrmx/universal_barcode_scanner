import 'package:flutter/widgets.dart';

/// [child] as it is: off the web, nothing under the buttons keeps the pointer
/// from them.
class PointerShield extends StatelessWidget {
  /// Shows [child].
  const PointerShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
