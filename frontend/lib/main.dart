import 'dart:convert';
import 'dart:ui'; // For ImageFilter
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'constants.dart';

// --- CONFIGURATION ---
const String BACKEND_URL = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8000/api',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: kIsWeb
        ? const FirebaseOptions(
        apiKey: "AIzaSyCbelvYReBwSTLUq5zMzbIHCA1WnmI_llE",
        authDomain: "ai-email-assistant-fb240.firebaseapp.com",
        projectId: "ai-email-assistant-fb240",
        storageBucket: "ai-email-assistant-fb240.firebasestorage.app",
        messagingSenderId: "925737234244",
        appId: "1:925737234244:web:a0d2cd8f4dce13775cb111",
        measurementId: "G-MXX5SBPEXF")
        : null,
  );
  runApp(const MyApp());
}

// --- THEME & STYLES ---
class AppColors {
  static const primary = Color(0xFF6366F1); // Indigo
  static const secondary = Color(0xFFEC4899); // Pink
  // Gradients for Dashboard
  static const bgGradientDark = [Color(0xFF0F172A), Color(0xFF1E1B4B)]; // Slate to Deep Indigo
  static const bgGradientLight = [Color(0xFFF8FAFC), Color(0xFFE0E7FF)]; // White to Soft Indigo
}

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light),
  textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
  cardTheme: CardThemeData(
    elevation: 4,
    shadowColor: Colors.black.withOpacity(0.05),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: Colors.white,
  ),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark),
  textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  cardTheme: CardThemeData(
    elevation: 8,
    shadowColor: Colors.black.withOpacity(0.3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: const Color(0xFF1E293B),
  ),
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDark = true;
  User? _currentUser;
  String? _accessToken;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) => setState(() => _currentUser = user));
  }

  void toggleTheme() => setState(() => _isDark = !_isDark);
  void handleLogin(User user, String token) => setState(() { _currentUser = user; _accessToken = token; });
  void handleLogout() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    setState(() { _currentUser = null; _accessToken = null; });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inbox AI',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: _currentUser == null
          ? LandingScreen(onLoginSuccess: handleLogin, isDark: _isDark)
          : DashboardScreen(user: _currentUser!, accessToken: _accessToken, onLogout: handleLogout, toggleTheme: toggleTheme, isDark: _isDark),
    );
  }
}

// ---------------------------------------------------------------------------
// --- LANDING SCREEN ---
// ---------------------------------------------------------------------------
class LandingScreen extends StatefulWidget {
  final Function(User, String) onLoginSuccess;
  final bool isDark;
  const LandingScreen({super.key, required this.onLoginSuccess, required this.isDark});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? "925737234244-kkt8s442hdu1juck1kg8vvs4943mal83.apps.googleusercontent.com" : null,
        scopes: ['email', 'https://www.googleapis.com/auth/gmail.modify'],
      );
      final acc = await googleSignIn.signIn();
      if (acc == null) { setState(() => _isLoading = false); return; }

      final auth = await acc.authentication;
      final cred = GoogleAuthProvider.credential(accessToken: auth.accessToken, idToken: auth.idToken);
      final userCred = await FirebaseAuth.instance.signInWithCredential(cred);

      if (userCred.user != null && auth.accessToken != null) {
        widget.onLoginSuccess(userCred.user!, auth.accessToken!);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Login Error: $e")));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = widget.isDark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          // --- 1. Animated Background Bubbles ---
          Positioned(top: -50, left: -50, child: _AnimatedBubble(controller: _controller, color: Colors.purpleAccent, size: 300, offset: 20)),
          Positioned(bottom: -100, right: -50, child: _AnimatedBubble(controller: _controller, color: Colors.blueAccent, size: 400, offset: -30)),
          Positioned(top: size.height * 0.3, right: size.width * 0.2, child: _AnimatedBubble(controller: _controller, color: Colors.pinkAccent.withOpacity(0.5), size: 150, offset: 40)),

          // --- 2. Glassmorphic Content Card ---
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: min(400, size.width * 0.9),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.auto_awesome, size: 40, color: AppColors.primary),
                      ),
                      const SizedBox(height: 24),
                      Text("Inbox AI", style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                      const SizedBox(height: 8),
                      Text("Your intelligent, privacy-first email assistant.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                      const SizedBox(height: 40),

                      // Sign In Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _signIn,
                          icon: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Image.asset("assets/google.png",height: 24,),
                          label: Text(_isLoading ? "Connecting..." : "Continue with Google", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.white : Colors.black,
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),

                      // Footer Terms
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          _FooterLink("Terms of Service"),
                          Text("•", style: TextStyle(color: Colors.grey[500])),
                          _FooterLink("Privacy Policy"),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBubble extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final double size;
  final double offset;

  const _AnimatedBubble({required this.controller, required this.color, required this.size, required this.offset});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            sin(controller.value * 2 * pi) * offset,
            cos(controller.value * 2 * pi) * offset,
          ),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.4),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- HELPER FUNCTION TO CALL FROM ANYWHERE ---
void showPolicyDialog(BuildContext context, String title, String markdownContent) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "Close",
    barrierColor: Colors.black.withOpacity(0.5), // Dim the screen behind the popup
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, anim1, anim2) {
      return _PolicyPopup(title: title, content: markdownContent);
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: child,
        ),
      );
    },
  );
}

// --- THE GLASSMORPHIC POPUP WIDGET ---
class _PolicyPopup extends StatefulWidget {
  final String title;
  final String content;
  const _PolicyPopup({required this.title, required this.content});

  @override
  State<_PolicyPopup> createState() => _PolicyPopupState();
}

class _PolicyPopupState extends State<_PolicyPopup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Independent animation controller for the popup bubbles
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // --- 1. Background Bubbles (Reusing the look from Landing) ---
          // Note: We reuse the _AnimatedBubble class you already have in main.dart
          Positioned(top: 100, left: -50, child: _AnimatedBubble(controller: _controller, color: Colors.purpleAccent, size: 200, offset: 20)),
          Positioned(bottom: 100, right: -50, child: _AnimatedBubble(controller: _controller, color: Colors.blueAccent, size: 300, offset: -30)),

          // --- 2. The Glass Card ---
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B).withOpacity(0.7) : Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, spreadRadius: 5)
                      ],
                    ),
                    child: Column(
                      children: [
                        // --- Header ---
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(widget.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop(),
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                                ),
                              )
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // --- Markdown Content ---
                        Expanded(
                          child: Markdown(
                            data: widget.content,
                            padding: const EdgeInsets.all(24),
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
                              h1: const TextStyle(color: Colors.transparent,fontSize: 0), // Hide h1 as we use the dialog title
                              h3: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                              blockSpacing: 16,
                            ),
                          ),
                        ),

                        // --- Footer Button ---
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                backgroundColor: Colors.deepPurpleAccent.withOpacity(0.8),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("Close", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String text;
  const _FooterLink(this.text);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // Determine which text to show based on the link label
        final content = text == "Privacy Policy" ? privacyPolicyText : termsOfServiceText;
        showPolicyDialog(context, text, content);
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// --- DASHBOARD SCREEN (GRADIENT & RESPONSIVE) ---
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  final User user;
  final String? accessToken;
  final VoidCallback onLogout;
  final VoidCallback toggleTheme;
  final bool isDark;
  const DashboardScreen({super.key, required this.user, required this.accessToken, required this.onLogout, required this.toggleTheme, required this.isDark});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedCategory = "All";
  List<dynamic> _emails = [];
  dynamic _selectedEmail;
  bool _isLoading = false;
  bool _isSyncing = false;

  @override
  void initState() { super.initState(); _fetchEmails(); }

  Future<void> _fetchEmails() async {
    if (widget.user.email == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$BACKEND_URL/emails/${widget.user.email}?category=$_selectedCategory'));
      if (res.statusCode == 200) setState(() => _emails = jsonDecode(res.body));
      else if (res.statusCode == 404) setState(() => _emails = []);
    } catch (e) { _notify("Error: $e", true); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _syncGmail() async {
    if (widget.accessToken == null) return _notify("Re-login required", true);
    setState(() => _isSyncing = true);
    try {
      final res = await http.post(Uri.parse('$BACKEND_URL/sync'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'token': widget.accessToken}));
      if (res.statusCode == 200) { _notify("Synced!"); _fetchEmails(); }
      else throw Exception(res.body);
    } catch (e) { _notify("Sync Failed", true); }
    finally { setState(() => _isSyncing = false); }
  }

  Future<void> _deleteEmail(String id) async {
    try {
      final res = await http.delete(Uri.parse('$BACKEND_URL/emails/${widget.user.email}/$id'));
      if (res.statusCode == 200) {
        setState(() {
          _emails.removeWhere((e) => e['id'] == id);
          // If the deleted email was selected, clear selection
          if (_selectedEmail != null && _selectedEmail['id'] == id) {
            _selectedEmail = null;
          }
        });
        _notify("Deleted");
      }
    } catch (e) { _notify("Delete Failed", true); }
  }

  void _notify(String msg, [bool err = false]) {
    if(!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => Positioned(top: 0, left: 0, right: 0, child: _TopPopup(message: msg, isError: err, onDismiss: () => entry.remove())));
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;

    // We wrap everything in a Container with the gradient
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDark ? AppColors.bgGradientDark : AppColors.bgGradientLight,
        ),
      ),
      child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  Widget _buildMobileLayout() {
    // Mobile: Show Detail if selected, else List
    if (_selectedEmail != null) {
      return PopScope(
        canPop: false,
        onPopInvoked: (didPop) { if (!didPop) setState(() => _selectedEmail = null); },
        child: Scaffold(
          backgroundColor: Colors.transparent, // Let gradient show
          appBar: AppBar(
              backgroundColor: Colors.transparent,
              leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _selectedEmail = null)),
              title: Text(_selectedEmail['subject'] ?? "Email", overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              actions: [IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteEmail(_selectedEmail['id']))]
          ),
          body: EmailDetailView(email: _selectedEmail, accessToken: widget.accessToken, onDelete: () => _deleteEmail(_selectedEmail['id']), isMobile: true),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // Let gradient show
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text("Inbox AI", style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [IconButton(icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode), onPressed: widget.toggleTheme)]
      ),
      drawer: Drawer(
        // Sidebar needs glass effect since it overlays
        child: _Sidebar(category: _selectedCategory, onSelect: (c) { setState(() => _selectedCategory = c); _fetchEmails(); Navigator.pop(context); }, onSync: _syncGmail, onLogout: widget.onLogout, isSyncing: _isSyncing, isDark: widget.isDark, onTheme: widget.toggleTheme),
      ),
      body: _buildEmailList(),
      floatingActionButton: FloatingActionButton(onPressed: _syncGmail, child: _isSyncing ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.sync)),
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: Colors.transparent, // Let gradient show
      body: Row(
        children: [
          SizedBox(width: 260, child: _Sidebar(category: _selectedCategory, onSelect: (c) { setState(() { _selectedCategory = c; _selectedEmail = null; }); _fetchEmails(); }, onSync: _syncGmail, onLogout: widget.onLogout, isSyncing: _isSyncing, isDark: widget.isDark, onTheme: widget.toggleTheme)),
          Container(width: 1, color: Theme.of(context).dividerColor.withOpacity(0.1)),
          SizedBox(width: 380, child: Column(children: [
            _ListHeader(_selectedCategory, _emails.length),
            Expanded(child: _buildEmailList())
          ])),
          Container(width: 1, color: Theme.of(context).dividerColor.withOpacity(0.1)),
          Expanded(child: _selectedEmail == null ? const Center(child: Text("Select an email to view details", style: TextStyle(color: Colors.grey))) : EmailDetailView(email: _selectedEmail, accessToken: widget.accessToken, onDelete: () => _deleteEmail(_selectedEmail['id']), isMobile: false)),
        ],
      ),
    );
  }

  Widget _buildEmailList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_emails.isEmpty) return const Center(child: Text("No emails found", style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _emails.length,
      itemBuilder: (ctx, i) => _EmailTile(email: _emails[i], isSelected: _selectedEmail?['id'] == _emails[i]['id'], onTap: () => setState(() => _selectedEmail = _emails[i])),
    );
  }
}

// --- WIDGETS ---

class _Sidebar extends StatelessWidget {
  final String category;
  final Function(String) onSelect;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final VoidCallback onTheme;
  final bool isSyncing;
  final bool isDark;
  const _Sidebar({required this.category, required this.onSelect, required this.onSync, required this.onLogout, required this.isSyncing, required this.isDark, required this.onTheme});

  @override
  Widget build(BuildContext context) {
    // Glassmorphic Sidebar
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.all(24), child: Row(children: [const Icon(Icons.mark_email_read, color: AppColors.primary), const SizedBox(width: 12), const Text("Inbox AI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const Spacer(), IconButton(icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 20), onPressed: onTheme)])),
              _navItem(context, "All Emails", Icons.all_inbox, "All"),
              const Divider(indent: 20, endIndent: 20, height: 30),
              _header("SMART FOLDERS"),
              _navItem(context, "Business", Icons.business_center, "Business"),
              _navItem(context, "Personal", Icons.person, "Personal"),
              _navItem(context, "Promotional", Icons.local_offer, "Promotional"),
              _navItem(context, "Spam", Icons.warning_amber, "Spam"),
              const Spacer(),
              Padding(padding: const EdgeInsets.all(20),
                  child: FilledButton.icon(
                      onPressed: isSyncing ? null : onSync,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.8),
                        foregroundColor: Colors.white,
                      ),
                      icon: isSyncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.sync), label: const Text("Sync Gmail"))),
              TextButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent), label: const Text("Logout", style: TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
  Widget _header(String t) => Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2))));
  Widget _navItem(BuildContext ctx, String t, IconData i, String c) {
    final sel = category == c;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), child: ListTile(leading: Icon(i, size: 20, color: sel ? AppColors.primary : Colors.grey), title: Text(t, style: TextStyle(fontWeight: sel ? FontWeight.w600 : FontWeight.normal, fontSize: 14)), onTap: () => onSelect(c), selected: sel, selectedTileColor: AppColors.primary.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }
}

class _ListHeader extends StatelessWidget {
  final String c; final int n;
  const _ListHeader(this.c, this.n);
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)))), child: Row(children: [Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text("$n", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary)))]));
  }
}

class _EmailTile extends StatelessWidget {
  final dynamic email;
  final bool isSelected;
  final VoidCallback onTap;
  const _EmailTile({required this.email, required this.isSelected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isSelected ? AppColors.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
          child: Text((email['sender'] ?? "U")[0].toUpperCase()),
        ),
        title: Row(children: [
          Expanded(child: Text(email['sender'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 14))),
          Text(DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch(email['timestamp'])), style: TextStyle(fontSize: 11, color: Colors.grey[500]))
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text(email['subject'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          if (email['summary'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(email['summary'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color))),
          const SizedBox(height: 8),
          _CategoryTag(email['category']),
        ]),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  final String? cat;
  const _CategoryTag(this.cat);
  @override
  Widget build(BuildContext context) {
    Color c = Colors.grey;
    if (cat == "Business") c = Colors.blueAccent;
    if (cat == "Personal") c = Colors.green;
    if (cat == "Promotional") c = Colors.orange;
    if (cat == "Spam") c = Colors.red;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(cat ?? "?", style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)));
  }
}

class EmailDetailView extends StatefulWidget {
  final dynamic email; final String? accessToken; final VoidCallback onDelete; final bool isMobile;
  const EmailDetailView({super.key, required this.email, required this.accessToken, required this.onDelete, required this.isMobile});
  @override
  State<EmailDetailView> createState() => _EDVS();
}

class _EDVS extends State<EmailDetailView> {
  final _iCtrl = TextEditingController(), _dCtrl = TextEditingController();
  bool _gen = false, _hasD = false, _snd = false;
  @override
  void didUpdateWidget(covariant EmailDetailView o) { super.didUpdateWidget(o); if (o.email != widget.email) { _iCtrl.clear(); _dCtrl.clear(); _hasD = false; } }

  Future<void> _apiCall(String ep, Map b, Function(Map) succ) async {
    setState(() => ep == 'generate-reply' ? _gen = true : _snd = true);
    try {
      final res = await http.post(Uri.parse('$BACKEND_URL/$ep'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(b));
      if (res.statusCode == 200) succ(jsonDecode(res.body)); else throw Exception(res.body);
    } catch (e) { _notify("Error: $e",true); }
    finally { setState(() => ep == 'generate-reply' ? _gen = false : _snd = false); }
  }

  void _notify(String msg, [bool err = false]) {
    if(!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => Positioned(top: 0, left: 0, right: 0, child: _TopPopup(message: msg, isError: err, onDismiss: () => entry.remove())));
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!widget.isMobile) Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)))), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: widget.onDelete), const SizedBox(width: 8), OutlinedButton.icon(onPressed: () async { await launchUrl(Uri.parse("https://mail.google.com/mail/u/0/#inbox/${widget.email['threadId']}")); }, icon: const Icon(Icons.open_in_new, size: 16), label: const Text("Open Gmail"))])),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.email['subject'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.3)),
          const SizedBox(height: 20),
          Row(children: [CircleAvatar(child: Text(widget.email['sender'][0])), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.email['sender'], style: const TextStyle(fontWeight: FontWeight.bold)), Text("to me", style: TextStyle(fontSize: 12, color: Colors.grey[500]))])]),
          const SizedBox(height: 32),
          if (widget.email['summary'] != null) Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.auto_awesome, size: 18, color: AppColors.primary), const SizedBox(width: 8), const Text("AI Summary", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary))]), const SizedBox(height: 8), MarkdownBody(data: widget.email['summary'])])),
          const SizedBox(height: 32),
          MarkdownBody(data: widget.email['body'], styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: const TextStyle(fontSize: 16, height: 1.6)))
        ]))),
        // Reply Box
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!_hasD) ...[
            const Text("Quick Reply", style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _iCtrl,
                    decoration: InputDecoration(
                      hintText: "E.g., Accept and suggest 3pm...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: _gen
                      ? null
                      : () => _apiCall(
                    'generate-reply',
                    {
                      'email_content': widget.email['body'],
                      'sender_name': widget.email['sender'],
                      'intent': _iCtrl.text,
                    },
                        (d) => setState(() {
                      _dCtrl.text = d['reply'];
                      _hasD = true;
                    }),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,   // 👈 custom color here
                    foregroundColor: Colors.white,        // icon/spinner color
                  ),
                  icon: _gen
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.auto_awesome),
                ),
              ],
            )
          ] else ...[
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:
                [
                  const Text("Review Draft", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _hasD = false))
                ]
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _dCtrl,
                maxLines: 5,
                decoration: InputDecoration(
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none)
                )
            ),
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                    onPressed: _snd ? null : () => _apiCall('send-email', {'token': widget.accessToken, 'threadId': widget.email['threadId'], 'to': widget.email['sender'], 'subject': widget.email['subject'], 'body': _dCtrl.text},
                            (d) { _notify("Sent!"); setState(() { _hasD = false; _iCtrl.clear(); _dCtrl.clear(); }); }),
                    icon: _snd ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white)) : const Icon(Icons.send), label: const Text("Send")))
          ]
        ]))
      ],
    );
  }
}

class _TopPopup extends StatefulWidget {
  final String message; final bool isError; final VoidCallback onDismiss;
  const _TopPopup({required this.message, required this.isError, required this.onDismiss});
  @override
  State<_TopPopup> createState() => _TopPopupState();
}

class _TopPopupState extends State<_TopPopup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _offsetAnimation = Tween<Offset>(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _timer = Timer(const Duration(seconds: 3), () { if (mounted) _controller.reverse().then((_) => widget.onDismiss()); });
  }
  @override
  void dispose() { _controller.dispose(); _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.isError ? Colors.redAccent : Colors.green;
    final icon = widget.isError ? Icons.error_outline : Icons.check_circle;
    return SafeArea(child: SlideTransition(position: _offsetAnimation, child: Align(alignment: Alignment.topCenter, child: Container(margin: const EdgeInsets.only(top: 16, left: 20, right: 20), constraints: const BoxConstraints(maxWidth: 380), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: accent.withOpacity(0.3), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: accent, size: 20), const SizedBox(width: 12), Flexible(child: Text(widget.message, style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontWeight: FontWeight.w500, fontSize: 14, decoration: TextDecoration.none)))])))));
  }
}
