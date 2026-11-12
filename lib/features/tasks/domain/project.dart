/// A named container for a tree of tasks.
final class Project {
  const Project({required this.id, required this.name, required this.position});

  final String id;
  final String name;
  final int position;
}
