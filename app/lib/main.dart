import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crop_batches_page.dart';
import 'operations_hub_page.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hasConfig = _supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty;
  Object? initializationError;

  if (hasConfig) {
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabasePublishableKey,
      );
    } catch (error) {
      initializationError = error;
    }
  }

  runApp(TeplitsaProApp(
    supabaseConfigured: hasConfig && initializationError == null,
    initializationError: initializationError,
  ));
}

class TeplitsaProApp extends StatelessWidget {
  const TeplitsaProApp({
    required this.supabaseConfigured,
    this.initializationError,
    super.key,
  });

  final bool supabaseConfigured;
  final Object? initializationError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ТЕПЛИЦА PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF287A4B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: initializationError != null
          ? _SimpleMessagePage(
              title: 'Не удалось подключить Supabase',
              message: 'Проверь параметры подключения. Подробности: $initializationError',
            )
          : supabaseConfigured
              ? const AuthGate()
              : const DashboardPage(supabaseConfigured: false),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final GoTrueClient _auth;
  StreamSubscription<AuthState>? _subscription;
  User? _user;
  String? _authStreamError;

  @override
  void initState() {
    super.initState();
    _auth = Supabase.instance.client.auth;
    _user = _auth.currentUser;
    _subscription = _auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          _user = state.session?.user;
          _authStreamError = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() => _authStreamError = error.toString());
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authStreamError != null) {
      return _RetryPage(
        title: 'Проблема с обновлением сеанса',
        message: 'Проверь соединение. Подробности: $_authStreamError',
        onRetry: () => setState(() => _authStreamError = null),
      );
    }
    final user = _user;
    return user == null ? const AuthPage() : OrganizationGate(key: ValueKey(user.id), user: user);
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final email = _email.text.trim().toLowerCase();
      if (_signUp) {
        final response = await Supabase.instance.client.auth.signUp(
          email: email,
          password: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _isError = false;
          _message = response.session == null
              ? 'Учётная запись создана. Проверь почту и подтверди адрес, затем войди в приложение.'
              : 'Регистрация завершена. Выполняется вход.';
        });
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      final text = error.message.toLowerCase();
      setState(() {
        _isError = true;
        if (text.contains('invalid login credentials')) {
          _message = 'Неверный email или пароль.';
        } else if (text.contains('email not confirmed')) {
          _message = 'Сначала подтверди email по ссылке из письма.';
        } else if (text.contains('user already registered')) {
          _message = 'Этот email уже зарегистрирован. Переключись на «Войти».';
        } else {
          _message = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _message = 'Не удалось связаться с Supabase. Проверь интернет и настройки проекта.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.eco_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'ТЕПЛИЦА PRO',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _signUp ? 'Создание тестовой учётной записи' : 'Вход в систему',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Электронная почта',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final valueText = value?.trim() ?? '';
                          return valueText.contains('@') ? null : 'Введи корректный email';
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _hidePassword,
                        autofillHints: _signUp
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword ? 'Показать пароль' : 'Скрыть пароль',
                            onPressed: () => setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                          ),
                        ),
                        validator: (value) {
                          final password = value ?? '';
                          if (password.isEmpty) return 'Введи пароль';
                          if (_signUp && password.length < 8) {
                            return 'Используй не менее 8 символов';
                          }
                          return null;
                        },
                      ),
                      if (_signUp) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Повтори пароль',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value == _password.text
                              ? null
                              : 'Пароли не совпадают',
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _isError
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_signUp ? 'Создать учётную запись' : 'Войти'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _signUp = !_signUp;
                                  _message = null;
                                }),
                        child: Text(
                          _signUp
                              ? 'Уже есть аккаунт? Войти'
                              : 'Создать тестовую учётную запись',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Пока используй только тестовые данные. Не передавай пароль другим людям.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrganizationGate extends StatefulWidget {
  const OrganizationGate({required this.user, super.key});

  final User user;

  @override
  State<OrganizationGate> createState() => _OrganizationGateState();
}

class _OrganizationGateState extends State<OrganizationGate> {
  late Future<List<Map<String, dynamic>>> _memberships;

  @override
  void initState() {
    super.initState();
    _memberships = _loadMemberships();
  }

  Future<List<Map<String, dynamic>>> _loadMemberships() async {
    final rows = await Supabase.instance.client
        .from('memberships')
        .select('organization_id, role, organizations(name)')
        .eq('user_id', widget.user.id)
        .eq('active', true);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  String _organizationName(Map<String, dynamic> membership) {
    final organization = membership['organizations'];
    if (organization is Map) {
      return organization['name']?.toString() ?? 'Хозяйство';
    }
    return 'Хозяйство';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _memberships,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingPage(message: 'Загружаем хозяйства…');
        }
        if (snapshot.hasError) {
          return _RetryPage(
            title: 'Не удалось загрузить хозяйства',
            message: 'Проверь доступ к базе. Подробности: ${snapshot.error}',
            onRetry: () => setState(() => _memberships = _loadMemberships()),
          );
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return _CreateOrganizationPage(
            userEmail: widget.user.email ?? '',
            onCreated: () => setState(() => _memberships = _loadMemberships()),
          );
        }
        if (rows.length == 1) {
          final membership = rows.single;
          return DashboardPage(
            supabaseConfigured: true,
            organizationId: membership['organization_id']?.toString(),
            organizationName: _organizationName(membership),
            userEmail: widget.user.email,
            userRole: membership['role']?.toString(),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Выбери хозяйство')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Для этой учётной записи доступно несколько хозяйств.'),
              const SizedBox(height: 12),
              for (final membership in rows)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warehouse_outlined),
                    title: Text(_organizationName(membership)),
                    subtitle: Text('Роль: ${membership['role'] ?? 'участник'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DashboardPage(
                            supabaseConfigured: true,
                            organizationId: membership['organization_id']?.toString(),
                            organizationName: _organizationName(membership),
                            userEmail: widget.user.email,
                            userRole: membership['role']?.toString(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Выйти'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CreateOrganizationPage extends StatefulWidget {
  const _CreateOrganizationPage({
    required this.userEmail,
    required this.onCreated,
  });

  final String userEmail;
  final VoidCallback onCreated;

  @override
  State<_CreateOrganizationPage> createState() => _CreateOrganizationPageState();
}

class _CreateOrganizationPageState extends State<_CreateOrganizationPage> {
  final _name = TextEditingController(text: 'Моё тепличное хозяйство');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введи название хозяйства.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'create_organization',
        params: {'p_name': name},
      );
      if (mounted) widget.onCreated();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = 'Не удалось создать хозяйство: ${error.message}');
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось создать хозяйство. Проверь соединение.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Первоначальная настройка'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: _busy ? null : () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.warehouse_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      'Создай первое хозяйство',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Вход выполнен как ${widget.userEmail}. Эта учётная запись станет владельцем хозяйства.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _name,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Название хозяйства',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _create,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Создать хозяйство'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.supabaseConfigured,
    this.organizationId,
    this.organizationName,
    this.userEmail,
    this.userRole,
    super.key,
  });

  final bool supabaseConfigured;
  final String? organizationId;
  final String? organizationName;
  final String? userEmail;
  final String? userRole;

  static const modules = <_ModuleInfo>[
    _ModuleInfo('Теплицы и зоны', Icons.warehouse_outlined),
    _ModuleInfo('Культуры и партии', Icons.grass_outlined),
    _ModuleInfo('Агрономический журнал', Icons.event_note_outlined),
    _ModuleInfo('Полив и подкормки', Icons.water_drop_outlined),
    _ModuleInfo('Защита растений', Icons.health_and_safety_outlined),
    _ModuleInfo('Склад', Icons.inventory_2_outlined),
    _ModuleInfo('Урожай и продажи', Icons.shopping_basket_outlined),
    _ModuleInfo('Финансы', Icons.account_balance_wallet_outlined),
    _ModuleInfo('Сотрудники и задачи', Icons.groups_outlined),
    _ModuleInfo('Отчёты', Icons.query_stats_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ТЕПЛИЦА PRO', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (supabaseConfigured)
            IconButton(
              tooltip: 'Выйти',
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 4
              : constraints.maxWidth >= 650
                  ? 3
                  : 2;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        organizationName ?? 'Панель управления',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (userEmail != null) ...[
                        const SizedBox(height: 6),
                        Text(userEmail!, style: const TextStyle(color: Colors.black54)),
                        if (userRole != null)
                          Text('Роль: $userRole', style: const TextStyle(color: Colors.black54)),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Учёт теплиц, выращивания, ресурсов, урожая и финансов в одном месте.',
                      ),
                      const SizedBox(height: 12),
                      Chip(
                        avatar: Icon(
                          supabaseConfigured ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                          size: 18,
                        ),
                        label: Text(
                          supabaseConfigured
                              ? 'Вход выполнен, хозяйство выбрано'
                              : 'Ожидает настройки Supabase',
                        ),
                      ),
                      const Text(
                        'Это начальный экран. Разделы и операции будут подключаться поэтапно.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      if (!supabaseConfigured) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Работа с реальными данными пока не включена.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Разделы хозяйства', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: modules.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (context, index) {
                  final module = modules[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (index == 0 && organizationId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => GreenhousesPage(
                                organizationId: organizationId!,
                                organizationName: organizationName ?? 'Хозяйство',
                                canManage: userRole == 'owner' || userRole == 'manager',
                              ),
                            ),
                          );
                          return;
                        }
                        if (index == 1 && organizationId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CropBatchesPage(
                                organizationId: organizationId!,
                                canManage: userRole == 'owner' ||
                                    userRole == 'manager' ||
                                    userRole == 'agronomist',
                              ),
                            ),
                          );
                          return;
                        }
                        if (index >= 5 && index <= 8 && organizationId != null) {
                          final initialTabIndex = switch (index) {
                            5 => 0, // Склад
                            6 => 2, // Урожай
                            7 => 6, // Расходы
                            8 => 7, // Команда
                            _ => 0,
                          };
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OperationsHubPage(
                                organizationId: organizationId!,
                                initialTabIndex: initialTabIndex,
                              ),
                            ),
                          );
                          return;
                        }
                        final message = index == 0
                            ? 'Сначала войди в хозяйство, чтобы вести список теплиц.'
                            : index == 1
                                ? 'Сначала войди в хозяйство, чтобы вести культуры и партии.'
                                : 'Раздел «${module.title}» будет подключён позже.';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(module.icon, size: 30),
                            Text(module.title, style: Theme.of(context).textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}


class GreenhousesPage extends StatefulWidget {
  const GreenhousesPage({
    required this.organizationId,
    required this.organizationName,
    required this.canManage,
    super.key,
  });

  final String organizationId;
  final String organizationName;
  final bool canManage;

  @override
  State<GreenhousesPage> createState() => _GreenhousesPageState();
}

class _GreenhousesPageState extends State<GreenhousesPage> {
  late Future<List<Map<String, dynamic>>> _records;

  @override
  void initState() {
    super.initState();
    _records = _loadRecords();
  }

  Future<List<Map<String, dynamic>>> _loadRecords() async {
    final client = Supabase.instance.client;
    final greenhouseRows = await client
        .from('greenhouses')
        .select('id, name, area, area_unit, notes')
        .eq('organization_id', widget.organizationId)
        .eq('active', true)
        .order('created_at');
    final zoneRows = await client
        .from('greenhouse_zones')
        .select('id, greenhouse_id, name, area, area_unit, notes')
        .eq('organization_id', widget.organizationId)
        .eq('active', true)
        .order('created_at');

    final zonesByGreenhouse = <String, List<Map<String, dynamic>>>{};
    for (final rawZone in zoneRows) {
      final zone = Map<String, dynamic>.from(rawZone);
      final greenhouseId = zone['greenhouse_id']?.toString() ?? '';
      zonesByGreenhouse.putIfAbsent(greenhouseId, () => <Map<String, dynamic>>[]).add(zone);
    }

    return greenhouseRows.map((rawGreenhouse) {
      final greenhouse = Map<String, dynamic>.from(rawGreenhouse);
      final id = greenhouse['id']?.toString() ?? '';
      greenhouse['zones'] = zonesByGreenhouse[id] ?? <Map<String, dynamic>>[];
      return greenhouse;
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _records = _loadRecords());
    await _records;
  }


  Future<void> _editPlace(Map<String, dynamic> place, {required bool zone}) async {
    final draft = await showDialog<_PlaceDraft>(
      context: context,
      builder: (_) => _PlaceFormDialog(
        title: zone ? 'Изменить зону' : 'Изменить теплицу',
        nameLabel: zone ? 'Название зоны' : 'Название теплицы',
        initialDraft: _PlaceDraft(
          name: place['name']?.toString() ?? '',
          area: double.tryParse(place['area']?.toString() ?? ''),
          areaUnit: place['area_unit']?.toString() ?? 'm2',
          notes: place['notes']?.toString(),
        ),
      ),
    );
    if (draft == null || !mounted) return;
    final table = zone ? 'greenhouse_zones' : 'greenhouses';
    try {
      await Supabase.instance.client.from(table).update({
        'name': draft.name,
        'area': draft.area,
        'area_unit': draft.areaUnit,
        'notes': draft.notes,
      }).eq('id', place['id'].toString())
        .eq('organization_id', widget.organizationId);
      if (!mounted) return;
      await _refresh();
      _showError(zone ? 'Данные зоны обновлены.' : 'Данные теплицы обновлены.');
    } on PostgrestException catch (error) {
      if (mounted) _showError('Не удалось сохранить изменения: ${error.message}');
    } catch (_) {
      if (mounted) _showError('Не удалось сохранить изменения. Проверь подключение.');
    }
  }

  Future<void> _addGreenhouse() async {
    final draft = await showDialog<_PlaceDraft>(
      context: context,
      builder: (_) => const _PlaceFormDialog(
        title: 'Новая теплица',
        nameLabel: 'Название теплицы',
      ),
    );
    if (draft == null || !mounted) return;

    try {
      await Supabase.instance.client.from('greenhouses').insert({
        'organization_id': widget.organizationId,
        'name': draft.name,
        'area': draft.area,
        'area_unit': draft.areaUnit,
        'notes': draft.notes,
      });
      if (!mounted) return;
      setState(() => _records = _loadRecords());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Теплица добавлена.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      _showError('Не удалось добавить теплицу: ${error.message}');
    } catch (_) {
      if (!mounted) return;
      _showError('Не удалось добавить теплицу. Проверь подключение.');
    }
  }

  Future<void> _addZone(String greenhouseId, String greenhouseName) async {
    final draft = await showDialog<_PlaceDraft>(
      context: context,
      builder: (_) => _PlaceFormDialog(
        title: 'Новая зона',
        nameLabel: 'Название зоны',
        helperText: 'Теплица: $greenhouseName',
      ),
    );
    if (draft == null || !mounted) return;

    try {
      await Supabase.instance.client.from('greenhouse_zones').insert({
        'organization_id': widget.organizationId,
        'greenhouse_id': greenhouseId,
        'name': draft.name,
        'area': draft.area,
        'area_unit': draft.areaUnit,
        'notes': draft.notes,
      });
      if (!mounted) return;
      setState(() => _records = _loadRecords());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Зона добавлена.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      _showError('Не удалось добавить зону: ${error.message}');
    } catch (_) {
      if (!mounted) return;
      _showError('Не удалось добавить зону. Проверь подключение.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _areaLabel(dynamic area, dynamic unit) {
    if (area == null) return 'Площадь не указана';
    final unitCode = unit?.toString() ?? 'm2';
    final unitLabel = unitCode == 'ha'
        ? 'га'
        : unitCode == 'm2'
            ? 'м²'
            : unitCode;
    return '${area.toString()} $unitLabel';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Теплицы и зоны'),
        actions: [
          IconButton(
            tooltip: 'Обновить список',
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: _addGreenhouse,
              icon: const Icon(Icons.add),
              label: const Text('Добавить теплицу'),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingPage(message: 'Загружаем теплицы и зоны…');
          }
          if (snapshot.hasError) {
            return _RetryPage(
              title: 'Не удалось загрузить список',
              message: 'Проверь доступ к хозяйству. Подробности: ${snapshot.error}',
              onRetry: () => setState(() => _records = _loadRecords()),
            );
          }

          final greenhouses = snapshot.data ?? <Map<String, dynamic>>[];
          if (greenhouses.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 70),
                  const Icon(Icons.warehouse_outlined, size: 64, color: Colors.black38),
                  const SizedBox(height: 16),
                  Text(
                    'В хозяйстве пока нет теплиц',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Добавь первую теплицу, укажи площадь и затем создай зоны внутри неё.',
                    textAlign: TextAlign.center,
                  ),
                  if (!widget.canManage) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Добавлять теплицы может владелец или управляющий хозяйства.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  widget.organizationName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Теплиц: ${greenhouses.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final greenhouse in greenhouses)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: const Icon(Icons.warehouse_outlined),
                      title: Text(greenhouse['name']?.toString() ?? 'Теплица'),
                      subtitle: Text(_areaLabel(greenhouse['area'], greenhouse['area_unit'])),
                      trailing: widget.canManage
                          ? IconButton(
                              tooltip: 'Изменить теплицу',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editPlace(greenhouse, zone: false),
                            )
                          : null,
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        if ((greenhouse['notes']?.toString() ?? '').isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(greenhouse['notes'].toString()),
                            ),
                          ),
                        const Divider(height: 1),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 4),
                            child: Text(
                              'Зоны',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                        for (final rawZone in (greenhouse['zones'] as List<Map<String, dynamic>>))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.grid_view_outlined),
                            title: Text(rawZone['name']?.toString() ?? 'Зона'),
                            subtitle: Text(_areaLabel(rawZone['area'], rawZone['area_unit'])),
                            trailing: widget.canManage
                                ? IconButton(
                                    tooltip: 'Изменить зону',
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    onPressed: () => _editPlace(rawZone, zone: true),
                                  )
                                : null,
                          ),
                        if ((greenhouse['zones'] as List).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Зоны ещё не добавлены.'),
                            ),
                          ),
                        if (widget.canManage)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _addZone(
                                greenhouse['id'].toString(),
                                greenhouse['name'].toString(),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить зону'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlaceDraft {
  const _PlaceDraft({
    required this.name,
    required this.area,
    required this.areaUnit,
    required this.notes,
  });

  final String name;
  final double? area;
  final String areaUnit;
  final String? notes;
}

class _PlaceFormDialog extends StatefulWidget {
  const _PlaceFormDialog({
    required this.title,
    required this.nameLabel,
    this.helperText,
    this.initialDraft,
  });

  final String title;
  final String nameLabel;
  final String? helperText;
  final _PlaceDraft? initialDraft;

  @override
  State<_PlaceFormDialog> createState() => _PlaceFormDialogState();
}

class _PlaceFormDialogState extends State<_PlaceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _notes = TextEditingController();
  String _areaUnit = 'm2';

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    if (draft != null) {
      _name.text = draft.name;
      _area.text = draft.area?.toString() ?? '';
      _areaUnit = draft.areaUnit;
      _notes.text = draft.notes ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final areaText = _area.text.trim().replaceAll(',', '.');
    Navigator.of(context).pop(
      _PlaceDraft(
        name: _name.text.trim(),
        area: areaText.isEmpty ? null : double.parse(areaText),
        areaUnit: _areaUnit,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.helperText != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.helperText!),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: widget.nameLabel,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
                validator: (value) =>
                    (value?.trim().isNotEmpty ?? false) ? null : 'Укажи название.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _area,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Площадь (необязательно)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim().replaceAll(',', '.') ?? '';
                  if (text.isEmpty) return null;
                  final parsed = double.tryParse(text);
                  if (parsed == null || parsed <= 0) return 'Введи число больше нуля.';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _areaUnit,
                decoration: const InputDecoration(
                  labelText: 'Единица площади',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'm2', child: Text('м² — квадратные метры')),
                  DropdownMenuItem(value: 'ha', child: Text('га — гектары')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _areaUnit = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Примечание (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      );
}

class _RetryPage extends StatelessWidget {
  const _RetryPage({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Повторить')),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SimpleMessagePage extends StatelessWidget {
  const _SimpleMessagePage({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 44),
                  const SizedBox(height: 12),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ModuleInfo {
  const _ModuleInfo(this.title, this.icon);
  final String title;
  final IconData icon;
}
