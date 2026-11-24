import 'package:flutter/widgets.dart';

/// [child] as it is: off the web, nothing under the buttons keeps the pointer
/// from them.
class const PointerShield({super.key, required final Widget child})
    extends StatelessWidget {
  /// Shows [child].
  this;

  @override
  Widget build(BuildContext context) => child;
}
