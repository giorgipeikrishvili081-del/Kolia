import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolia/services/secrets.dart';

class TeamInfo {
  final String id;
  final String name;
  final String password;
  final Color color;
  final bool isAdmin;

  const TeamInfo({
    required this.id,
    required this.name,
    required this.password,
    required this.color,
    this.isAdmin = false,
  });
}

class AuthService {
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _teamIdKey = 'logged_team_id';
  static const String _customNameKey = 'custom_team_name';
  static const String _customColorKey = 'custom_team_color';

  static final List<TeamInfo> teams = [
    const TeamInfo(id: 'team_alpha', name: 'Team Alpha', password: AppSecrets.passwordAlpha, color: Colors.blue),
    const TeamInfo(id: 'team_beta', name: 'Team Beta', password: AppSecrets.passwordBeta, color: Colors.green),
    const TeamInfo(id: 'team_gamma', name: 'Team Gamma', password: AppSecrets.passwordGamma, color: Colors.orange),
    const TeamInfo(id: 'team_delta', name: 'Team Delta', password: AppSecrets.passwordDelta, color: Colors.purple),
    const TeamInfo(id: 'supervisor', name: 'Supervisor', password: AppSecrets.passwordAdmin, color: Colors.black, isAdmin: true),
  ];

  static Future<bool> login(String id, String password) async {
    final team = teams.firstWhere(
      (t) => t.id == id && t.password == password,
      orElse: () => const TeamInfo(id: '', name: '', password: '', color: Colors.transparent, isAdmin: false),
    );

    if (team.id.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isLoggedInKey, true);
      await prefs.setString(_teamIdKey, team.id);
      return true;
    }
    return false;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, false);
    await prefs.remove(_teamIdKey);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  static Future<TeamInfo?> getLoggedInTeam() async {
    final prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getString(_teamIdKey);
    if (teamId == null) return null;
    
    final baseTeam = teams.firstWhere((t) => t.id == teamId, orElse: () => teams[0]);
    
    final customName = prefs.getString('${_customNameKey}_$teamId');
    final customColorValue = prefs.getInt('${_customColorKey}_$teamId');
    
    return TeamInfo(
      id: baseTeam.id,
      name: customName ?? baseTeam.name,
      password: baseTeam.password,
      color: customColorValue != null ? Color(customColorValue) : baseTeam.color,
      isAdmin: baseTeam.isAdmin,
    );
  }

  static Future<void> updateTeamInfo({String? name, Color? color}) async {
    final prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getString(_teamIdKey);
    if (teamId == null) return;

    if (name != null) await prefs.setString('${_customNameKey}_$teamId', name);
    if (color != null) await prefs.setInt('${_customColorKey}_$teamId', color.value);
  }

  static Future<List<TeamInfo>> getTeamsWithCustomizations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force refresh from disk
    return teams.map((baseTeam) {
      final customName = prefs.getString('${_customNameKey}_${baseTeam.id}');
      final customColorValue = prefs.getInt('${_customColorKey}_${baseTeam.id}');
      
      return TeamInfo(
        id: baseTeam.id,
        name: customName ?? baseTeam.name,
        password: baseTeam.password,
        color: customColorValue != null ? Color(customColorValue) : baseTeam.color,
        isAdmin: baseTeam.isAdmin,
      );
    }).toList();
  }
}
