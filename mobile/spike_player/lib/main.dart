import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'player_screen.dart';

late SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Argosy Player Spike',
      theme: ThemeData.dark(useMaterial3: true),
      home: const Gate(),
    );
  }
}

/// Restores a saved token if present, else shows login.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  @override
  Widget build(BuildContext context) {
    final base = prefs.getString('baseUrl');
    final token = prefs.getString('token');
    if (base != null && token != null) {
      final api = ApiClient(base)..token = token;
      return LibrariesScreen(api: api);
    }
    return const LoginScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController(text: 'http://10.0.0.45:8097');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _status;
  bool _busy = false;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final api = ApiClient(_url.text.trim());
      final res = await api.login(_user.text.trim(), _pass.text);
      final profiles = (res['profiles'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final profile = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Choose profile'),
          children: [
            for (final p in profiles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text('${p['name']}  ·  ${p['role']}'),
              ),
          ],
        ),
      );
      if (profile == null) return;
      await api.registerDevice(_user.text.trim(), _pass.text,
          profile['id'] as String, 'Spike Phone');
      await prefs.setString('baseUrl', api.baseUrl);
      await prefs.setString('token', api.token!);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => LibrariesScreen(api: api)));
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Argosy — Player Spike')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Server URL')),
          TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Username')),
          TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _busy ? null : _login,
              child: Text(_busy ? '...' : 'Log in + register device')),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
        ]),
      ),
    );
  }
}

class LibrariesScreen extends StatefulWidget {
  final ApiClient api;
  const LibrariesScreen({super.key, required this.api});
  @override
  State<LibrariesScreen> createState() => _LibrariesScreenState();
}

class _LibrariesScreenState extends State<LibrariesScreen> {
  late Future<List<dynamic>> _libs;
  @override
  void initState() {
    super.initState();
    _libs = widget.api.libraries();
  }

  Future<void> _logout() async {
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Libraries'), actions: [
        IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
      ]),
      body: FutureBuilder<List<dynamic>>(
        future: _libs,
        builder: (_, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final libs = snap.data!;
          return ListView(children: [
            for (final l in libs)
              ListTile(
                leading: const Icon(Icons.folder),
                title: Text(l['name'] as String),
                subtitle: Text(l['kind'] as String),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MoviesScreen(
                            api: widget.api,
                            libraryId: l['id'] as String,
                            libraryName: l['name'] as String))),
              ),
          ]);
        },
      ),
    );
  }
}

class MoviesScreen extends StatefulWidget {
  final ApiClient api;
  final String libraryId;
  final String libraryName;
  const MoviesScreen(
      {super.key,
      required this.api,
      required this.libraryId,
      required this.libraryName});
  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  late Future<List<dynamic>> _movies;
  @override
  void initState() {
    super.initState();
    _movies = widget.api.movies(widget.libraryId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.libraryName)),
      body: FutureBuilder<List<dynamic>>(
        future: _movies,
        builder: (_, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final movies = snap.data!;
          if (movies.isEmpty) {
            return const Center(child: Text('No movies in this library'));
          }
          return ListView(children: [
            for (final m in movies)
              ListTile(
                leading: const Icon(Icons.movie),
                title: Text(m['title'] as String),
                subtitle: Text([
                  if (m['year'] != null) '${m['year']}',
                  ...((m['tags'] as List?)?.cast<String>() ?? const []),
                ].join(' · ')),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                            api: widget.api,
                            itemId: m['id'] as String,
                            title: m['title'] as String))),
              ),
          ]);
        },
      ),
    );
  }
}
