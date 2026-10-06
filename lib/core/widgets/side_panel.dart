import 'package:flutter/material.dart';

/// Closes whichever side panel of the nearest [Scaffold] is open.
///
/// For a choice made in a panel: the filter panel on the left and the menu
/// on the right both close on a tap, so what the person sees next is the
/// result. Closing through the [Scaffold] rather than `Navigator.pop` means
/// a widget shown outside a panel — a test, a sheet — never pops a route by
/// mistake.
void closeSidePanel(BuildContext context) {
  final scaffold = Scaffold.maybeOf(context);
  if (scaffold == null) return;
  if (scaffold.isDrawerOpen) scaffold.closeDrawer();
  if (scaffold.isEndDrawerOpen) scaffold.closeEndDrawer();
}
