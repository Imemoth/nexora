import 'package:flutter/material.dart';

/// One selectable row in the sidebar: icon, label and a count.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      leading: Icon(icon),
      title: Text(label, overflow: TextOverflow.ellipsis),
      trailing: Text(count.toString()),
      onTap: onTap,
    );
  }
}
