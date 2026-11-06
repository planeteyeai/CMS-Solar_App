import 'dart:math';

/// The four app experiences. Routing uses only the authenticated /me response.
enum AppRole { superAdmin, projectManager, teamLead, siteEngineer, other }

class ProjectAssignment {
  final int id;
  final String projectName;
  final String status;
  final bool isActive;

  const ProjectAssignment({
    required this.id,
    required this.projectName,
    required this.status,
    required this.isActive,
  });

  factory ProjectAssignment.fromJson(Map<String, dynamic> j) =>
      ProjectAssignment(
        id: _toInt(j['id']),
        projectName: (j['project_name'] ?? j['name'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        isActive: j['is_active'] == true,
      );
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class UserProfile {
  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String highestRole;
  final List<String> groups;
  final bool isStaff;
  final bool isSuperuser;
  final ProjectAssignment? assignedProject;
  final List<ProjectAssignment> assignedProjects;

  const UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.highestRole,
    required this.groups,
    required this.isStaff,
    required this.isSuperuser,
    required this.assignedProject,
    required this.assignedProjects,
  });

  static String normalizeRole(String value) =>
      value.trim().toUpperCase().replaceAll('-', '_').replaceAll(' ', '_');

  bool _hasRole(List<String> names) {
    final role = normalizeRole(highestRole);
    final g = groups.map(normalizeRole).toList();
    return names.contains(role) || g.any(names.contains);
  }

  bool get isSuperAdmin =>
      isSuperuser ||
      _hasRole(const ['SUPER_ADMIN', 'SUPERADMIN']) ||
      normalizeRole(username) == 'SUPERADMIN';

  bool get isProjectManager => _hasRole(const ['PROJECT_MANAGER']);

  bool get isTeamLead => _hasRole(const ['TEAM_LEAD', 'TEAM_LEADER']);

  bool get isSiteEngineer =>
      _hasRole(const ['SITE_ENGINEER']) ||
      normalizeRole(username) == 'SITEENGINEER';

  /// Highest role wins: Superadmin > Project Manager > Team Lead > Site Engineer.
  AppRole get appRole {
    if (isSuperAdmin) return AppRole.superAdmin;
    if (isProjectManager) return AppRole.projectManager;
    if (isTeamLead) return AppRole.teamLead;
    if (isSiteEngineer) return AppRole.siteEngineer;
    return AppRole.other;
  }

  String get primaryRole {
    switch (appRole) {
      case AppRole.superAdmin:
        return 'Superadmin';
      case AppRole.projectManager:
        return 'Project Manager';
      case AppRole.teamLead:
        return 'Team Lead';
      case AppRole.siteEngineer:
        return 'Site Engineer';
      case AppRole.other:
        return groups.isNotEmpty ? groups.first : (isStaff ? 'Staff' : 'User');
    }
  }

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isNotEmpty ? n : username;
  }

  String get initials {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    }
    return username.substring(0, min(2, username.length)).toUpperCase();
  }

  /// Project the user works on by default (assigned_project, else the first
  /// active one, else the first one).
  String? get primaryProjectName {
    if (assignedProject != null && assignedProject!.projectName.isNotEmpty) {
      return assignedProject!.projectName;
    }
    final active = assignedProjects.where((a) => a.isActive).toList();
    if (active.isNotEmpty) return active.first.projectName;
    return assignedProjects.isNotEmpty ? assignedProjects.first.projectName : null;
  }

  List<ProjectAssignment> get activeAssignments =>
      assignedProjects.where((a) => a.isActive).toList();

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final rawGroups = j['groups'];
    final groups = rawGroups is List
        ? rawGroups.map((e) => e.toString()).toList()
        : <String>[];
    final rawList = j['assigned_projects'] ?? j['active_assignments'];
    final projects = rawList is List
        ? rawList
            .whereType<Map>()
            .map((e) => ProjectAssignment.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ProjectAssignment>[];
    final rawOne = j['assigned_project'];
    return UserProfile(
      id: _toInt(j['id']),
      username: (j['username'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      firstName: (j['first_name'] ?? '').toString(),
      lastName: (j['last_name'] ?? '').toString(),
      highestRole: (j['highest_role'] ?? j['role'] ?? '').toString(),
      groups: groups,
      isStaff: j['is_staff'] == true,
      isSuperuser: j['is_superuser'] == true,
      assignedProject: rawOne is Map
          ? ProjectAssignment.fromJson(Map<String, dynamic>.from(rawOne))
          : null,
      assignedProjects: projects,
    );
  }
}
