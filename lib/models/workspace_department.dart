class WorkspaceDepartment {
  final String id;
  final String name;

  const WorkspaceDepartment({required this.id, required this.name});

  String get displayName {
    final value = name.trim();
    return value.isEmpty ? 'Department' : value;
  }
}
