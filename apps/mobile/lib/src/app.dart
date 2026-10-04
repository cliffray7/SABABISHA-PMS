import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/admin_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/workspace_shell.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/session_store.dart';
import 'widgets/common.dart';

class PmsApp extends StatefulWidget {
  const PmsApp({super.key});

  @override
  State<PmsApp> createState() => _PmsAppState();
}

class _PmsAppState extends State<PmsApp> {
  late final SessionStore _sessions;
  late final ApiClient _api;
  late final AppState _appState;
  ThemeMode _themeMode = ThemeMode.light;
  Future<bool>? _init;

  @override
  void initState() {
    super.initState();
    _sessions = const SessionStore(FlutterSecureStorage());
    _api = ApiClient(sessionStore: _sessions);
    _appState = AppState(_api);
    _init = _tryRestore();
  }

  Future<bool> _tryRestore() async {
    if (await _sessions.read() == null) return false;
    try {
      final account = await _api.account();
      _appState.account = account;
      await _appState.checkSuperAdmin();
      if (!_appState.isSuperAdmin) {
        await Future.wait([
          _appState.loadOrganizations(),
          _appState.loadNotifications(),
        ]);
      }
      return _appState.account != null;
    } on ApiException {
      await _sessions.clear();
      return false;
    } catch (_) {
      return false;
    }
  }

  void _handleSignedIn() {
    final future = _tryRestore();
    setState(() {
      _init = future;
    });
  }

  void _handleSignedOut() {
    _init = Future.value(false);
    setState(() {});
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: MaterialApp(
        title: 'Sababisha PMS',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: FutureBuilder<bool>(
          future: _init,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(
                backgroundColor: kPage,
                body: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(kViolet),
                  ),
                ),
              );
            }
            if (snap.data == true) {
              if (_appState.isSuperAdmin) {
                return AdminScreen(
                  onSignedOut: _handleSignedOut,
                  onToggleTheme: _toggleTheme,
                  themeMode: _themeMode,
                );
              }
              return WorkspaceShell(
                onSignedOut: _handleSignedOut,
                onToggleTheme: _toggleTheme,
                themeMode: _themeMode,
              );
            }
            return AuthPage(
              api: _api,
              onSignedIn: _handleSignedIn,
            );
          },
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final base = isLight ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      // ── DM Sans font — exact match to web ──────────────────────────────
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.dmSansTextTheme(base.primaryTextTheme),

      // ── Color scheme ──────────────────────────────────────────────────
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4D40ED),
        brightness: brightness,
        primary: const Color(0xFF4D40ED),
        onPrimary: Colors.white,
        secondary: kVioletLight,
        onSecondary: const Color(0xFF4D40ED),
        error: kDanger,
        surface: isLight ? kPanel : kPanelDark,
        onSurface: isLight ? kInk : const Color(0xFFEEF0F8),
        outline: kMuted,
        outlineVariant: kLine,
        surfaceContainerLowest: isLight ? kPage : kPageDark,
        surfaceContainerLow: isLight ? const Color(0xFFF7F7FA) : const Color(0xFF1A1C26),
        surfaceContainerHighest: isLight ? const Color(0xFFEEEDFF) : const Color(0xFF2A2D38),
      ),

      scaffoldBackgroundColor: isLight ? kPage : kPageDark,

      // ── AppBar — 56px height, white bg, 1px bottom border, no shadow ──
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? kPanel : kPanelDark,
        foregroundColor: isLight ? kInk : const Color(0xFFEEF0F8),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isLight ? kInk : const Color(0xFFEEF0F8),
        ),
        iconTheme: IconThemeData(
          color: isLight ? kInk : const Color(0xFFEEF0F8),
        ),
        shape: Border(
          bottom: BorderSide(
            color: isLight ? kLine : const Color(0xFF343845),
            width: 1,
          ),
        ),
        toolbarHeight: 56,
      ),

      // ── NavigationBar — web sidebar nav aesthetics ─────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? kPanel : kPanelDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: kVioletLight,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? kViolet : kMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? kViolet : kMuted,
            size: 22,
          );
        }),
      ),

      // ── Card — 0 elevation, 1px border, radius 8 ──────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? kPanel : kPanelDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isLight ? kLine : const Color(0xFF343845),
          ),
        ),
        margin: const EdgeInsets.only(bottom: 8),
      ),

      // ── Divider ───────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: kLine,
        thickness: 1,
        space: 1,
      ),

      // ── Input fields — 1px border, radius 4, 14px, 32px height ───────
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kViolet, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: kDanger),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
        fillColor: isLight ? kPanel : const Color(0xFF252834),
        filled: true,
        labelStyle: const TextStyle(fontSize: 13, color: kMuted),
        hintStyle: const TextStyle(fontSize: 13, color: kMuted),
        helperStyle: const TextStyle(fontSize: 12, color: kMuted),
        errorStyle: const TextStyle(fontSize: 12, color: kDanger),
      ),

      // ── FilledButton — exact web .primary ─────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kViolet,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 36),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),

      // ── OutlinedButton — exact web .secondary ─────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isLight ? kInk : const Color(0xFFEEF0F8),
          minimumSize: const Size(0, 36),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          side: const BorderSide(color: kLine),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── TextButton — link-button style ───────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kViolet,
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600),
          minimumSize: const Size(0, 32),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),

      // ── Checkbox ─────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? kViolet : null),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),

      // ── ListTile ──────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minLeadingWidth: 0,
        visualDensity: VisualDensity.compact,
      ),

      // ── TabBar — matching web .view-tabs ──────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: kViolet,
        unselectedLabelColor: kMuted,
        labelStyle: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w400),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: kViolet, width: 2),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: kLine,
      ),

      // ── SegmentedButton ───────────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: isLight ? const Color(0xFFF7F7FA) : kPanelDark,
          selectedBackgroundColor: kVioletLight,
          selectedForegroundColor: kViolet,
          foregroundColor: kMuted,
          side: const BorderSide(color: kLine),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmSans(fontSize: 12),
          minimumSize: const Size(0, 32),
        ),
      ),

      // ── ProgressIndicator — violet ───────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: kViolet,
        linearTrackColor: Color(0xFFE6E6ED),
      ),

      // ── Chip — role pill style ────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:
            isLight ? const Color(0xFFF0F0F6) : const Color(0xFF2A2D38),
        labelStyle: GoogleFonts.dmSans(
            fontSize: 11, color: const Color(0xFF777987)),
        padding: EdgeInsets.zero,
        labelPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),

      // ── Switch ────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? kViolet
                : Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? kVioletLight
                : kLine),
      ),

      // ── PopupMenu / DropdownMenu ──────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: isLight ? kPanel : kPanelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kLine),
        ),
        elevation: 4,
        textStyle: GoogleFonts.dmSans(fontSize: 14, color: isLight ? kInk : const Color(0xFFEEF0F8)),
      ),

      // ── AlertDialog ───────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? kPanel : kPanelDark,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        titleTextStyle: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isLight ? kInk : const Color(0xFFEEF0F8)),
        contentTextStyle: GoogleFonts.dmSans(
            fontSize: 14,
            color: isLight ? kInk : const Color(0xFFEEF0F8)),
      ),

      // ── SnackBar ──────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? kInk : const Color(0xFF2A2D38),
        contentTextStyle: GoogleFonts.dmSans(fontSize: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

