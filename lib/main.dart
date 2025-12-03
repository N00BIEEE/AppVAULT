import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('com.example.appvault/channel');

void main() {
  runApp(const AppVaultApp());
}

class AppVaultApp extends StatelessWidget {
  const AppVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppVault',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, String> _appNames = {}; // package -> app label
  List<String> _recentApps = []; // list of package names
  Map<String, Map<String, bool>> _permCategoriesByPkg = {}; // package -> category->granted

  bool _loadingRecent = false;
  bool _loadingPerms = false;
  bool _loadingApps = false;
  String? _error;

  // Search + filters for All Apps
  String _searchQuery = '';
  final Set<String> _selectedCategories = {};
  final List<String> _allCategories = const [
    'Camera',
    'Contacts',
    'Location',
    'Microphone',
    'Storage',
    'SMS',
    'Phone',
    'Sensors',
    'Activity',
    'Notifications',
  ];

  // Risk level filter: 'Dangerous', 'Moderate', 'Safe', or null for "All"
  String? _selectedRiskLevel; // null = All

  // ---- APK Scanner tab state ----
  Map<String, bool> _apkCategories = {};
  String? _apkName;
  String? _apkPackage;
  String? _apkRisk;
  String? _apkPath;
  bool _apkAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _loadAppList();
    await _loadPermissionCategories();
    await _loadRecentApps();
  }

  /// Get packageName -> app label from native getAppList()
  Future<void> _loadAppList() async {
    setState(() {
      _loadingApps = true;
      _error = null;
    });

    try {
      final result =
      await platform.invokeMethod<Map<dynamic, dynamic>>('getAppList');

      if (result != null) {
        setState(() {
          _appNames = result.map(
                (key, value) =>
                MapEntry(key as String, value?.toString() ?? key.toString()),
          );
        });
      }
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Failed to load app list: ${e.message}';
      });
    } finally {
      setState(() {
        _loadingApps = false;
      });
    }
  }

  /// Get packageName -> (permissionName -> granted) from native
  /// and convert to packageName -> (category -> granted)
  Future<void> _loadPermissionCategories() async {
    setState(() {
      _loadingPerms = true;
      _error = null;
    });

    try {
      final result = await platform
          .invokeMethod<Map<dynamic, dynamic>>('getGrantedPermissions');

      if (result == null) {
        setState(() {
          _permCategoriesByPkg = {};
        });
        return;
      }

      final Map<String, Map<String, bool>> tmp = {};

      result.forEach((pkgKey, permsValue) {
        final pkg = pkgKey as String;
        final permsMap = (permsValue as Map<dynamic, dynamic>?) ?? {};

        // rawPerms: full permission name -> granted?
        final Map<String, bool> rawPerms = {};
        permsMap.forEach((pKey, pVal) {
          final permName = pKey.toString();
          final granted = pVal == true;
          rawPerms[permName] = granted;
        });

        // category -> granted?
        final Map<String, bool> categories = {};

        rawPerms.forEach((permName, granted) {
          final category = _mapPermissionToCategory(permName);
          if (category == null) return;

          final prev = categories[category] ?? false;
          categories[category] = prev || granted;
        });

        tmp[pkg] = categories;
      });

      setState(() {
        _permCategoriesByPkg = tmp;
      });
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Failed to load permissions: ${e.message}';
      });
    } finally {
      setState(() {
        _loadingPerms = false;
      });
    }
  }

  /// Ask native for recent apps (list of package names)
  Future<void> _loadRecentApps() async {
    setState(() {
      _loadingRecent = true;
      _error = null;
    });

    try {
      final result =
      await platform.invokeListMethod<String>('getRecentApps');

      setState(() {
        _recentApps = result ?? [];
      });
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Failed to load recent apps: ${e.message}';
      });
    } finally {
      setState(() {
        _loadingRecent = false;
      });
    }
  }

  Future<void> _openUsageAccessSettings() async {
    try {
      await platform.invokeMethod('openUsageAccessSettings');
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Failed to open Usage Access settings: ${e.message}';
      });
    }
  }

  Future<void> _openAppSettings(String packageName) async {
    try {
      await platform.invokeMethod('openAppSettings', {
        'package': packageName,
      });
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Failed to open app settings: ${e.message}';
      });
    }
  }

  /// Map full Android permission string to a simple category
  String? _mapPermissionToCategory(String perm) {
    if (perm.contains('CAMERA')) return 'Camera';

    if (perm.contains('READ_CONTACTS') ||
        perm.contains('WRITE_CONTACTS') ||
        perm.contains('GET_ACCOUNTS')) {
      return 'Contacts';
    }

    if (perm.contains('ACCESS_FINE_LOCATION') ||
        perm.contains('ACCESS_COARSE_LOCATION') ||
        perm.contains('ACCESS_BACKGROUND_LOCATION')) {
      return 'Location';
    }

    if (perm.contains('RECORD_AUDIO')) return 'Microphone';

    if (perm.contains('READ_EXTERNAL_STORAGE') ||
        perm.contains('WRITE_EXTERNAL_STORAGE') ||
        perm.contains('MANAGE_EXTERNAL_STORAGE')) {
      return 'Storage';
    }

    if (perm.contains('READ_SMS') ||
        perm.contains('SEND_SMS') ||
        perm.contains('RECEIVE_SMS') ||
        perm.contains('READ_CELL_BROADCASTS')) {
      return 'SMS';
    }

    if (perm.contains('CALL_PHONE') ||
        perm.contains('READ_CALL_LOG') ||
        perm.contains('WRITE_CALL_LOG') ||
        perm.contains('ADD_VOICEMAIL')) {
      return 'Phone';
    }

    if (perm.contains('BODY_SENSORS')) return 'Sensors';

    if (perm.contains('ACTIVITY_RECOGNITION')) return 'Activity';

    if (perm.contains('POST_NOTIFICATIONS')) return 'Notifications';

    return null; // ignore un-mapped permissions
  }

  /// Compute a simple "risk level" string based on granted categories.
  String _computeRiskLevel(Map<String, bool> categories) {
    int sensitive = 0;
    int medium = 0;

    bool has(String cat) => categories[cat] == true;

    // sensitive
    if (has('Camera')) sensitive++;
    if (has('Location')) sensitive++;
    if (has('Microphone')) sensitive++;
    if (has('Storage')) sensitive++;
    if (has('SMS')) sensitive++;
    if (has('Phone')) sensitive++;

    // medium
    if (has('Contacts')) medium++;
    if (has('Sensors')) medium++;
    if (has('Activity')) medium++;
    if (has('Notifications')) medium++;

    final score = sensitive * 2 + medium;

    if (score >= 5) return 'Dangerous';
    if (score >= 2) return 'Moderate';
    return 'Safe';
  }

  // ---------- APK Scanner logic ----------

  Future<void> _pickAndAnalyzeApk() async {
    setState(() {
      _apkAnalyzing = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _apkAnalyzing = false;
        });
        return;
      }

      final path = result.files.single.path!;
      final res = await platform.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeApk',
        {'path': path},
      );

      if (res == null || res['ok'] != true) {
        setState(() {
          _apkAnalyzing = false;
          _apkName = null;
          _apkPackage = null;
          _apkCategories = {};
          _apkRisk = null;
          _apkPath = null;
        });
        return;
      }

      final label = res['label']?.toString() ?? 'Unknown';
      final pkg = res['package']?.toString() ?? 'Unknown';
      final perms = (res['permissions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      final Map<String, bool> cats = {};
      for (final p in perms) {
        final cat = _mapPermissionToCategory(p);
        if (cat == null) continue;
        cats[cat] = true;
      }

      final risk = _computeRiskLevel(cats);

      setState(() {
        _apkName = label;
        _apkPackage = pkg;
        _apkCategories = cats;
        _apkRisk = risk;
        _apkPath = path;
        _apkAnalyzing = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _apkAnalyzing = false;
        _error = 'Failed to analyze APK: ${e.message}';
      });
    }
  }

  Future<void> _installAnalyzedApk() async {
    if (_apkPath == null) return;
    try {
      await platform.invokeMethod('installApk', {'path': _apkPath});
    } on PlatformException catch (e) {
      setState(() {
        _error = 'Failed to start install: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoadingAny = _loadingApps || _loadingPerms || _loadingRecent;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AppVault'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.history), text: 'Recent Activity'),
              Tab(icon: Icon(Icons.apps), text: 'All Apps'),
              Tab(icon: Icon(Icons.download), text: 'APK Scanner'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openUsageAccessSettings,
                      icon: const Icon(Icons.visibility),
                      label: const Text('Usage Access Settings'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Refresh app data',
                    onPressed: () async {
                      await _loadAppList();
                      await _loadPermissionCategories();
                      await _loadRecentApps();
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (isLoadingAny) const LinearProgressIndicator(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildRecentTab(context),
                  _buildAllAppsTab(context),
                  _buildApkTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- TAB 1: RECENT ACTIVITY ----------

  Widget _buildRecentTab(BuildContext context) {
    final hasRecent = _recentApps.isNotEmpty;

    if (!hasRecent && !_loadingRecent) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No recent apps.\n\n'
                'Make sure Usage Access is granted for this app,\n'
                'then use some apps and tap refresh.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _recentApps.length,
      itemBuilder: (context, index) {
        final pkg = _recentApps[index];
        final label = _appNames[pkg] ?? pkg;
        final categories = _permCategoriesByPkg[pkg] ?? {};
        final risk = _computeRiskLevel(categories);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                label.isNotEmpty ? label[0].toUpperCase() : '?',
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(label)),
                const SizedBox(width: 6),
                _buildRiskBadge(risk),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pkg,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                _buildPermissionChips(categories),
              ],
            ),
            trailing: IconButton(
              tooltip: 'Open app settings',
              icon: const Icon(Icons.settings),
              onPressed: () => _openAppSettings(pkg),
            ),
          ),
        );
      },
    );
  }

  // ---------- TAB 2: ALL APPS (search + filters + risk) ----------

  Widget _buildAllAppsTab(BuildContext context) {
    if (_appNames.isEmpty && !_loadingApps) {
      return const Center(
        child: Text(
          'No apps found.\nTry refreshing.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final allPackages = _appNames.keys.toList()
      ..sort((a, b) {
        final nameA = _appNames[a] ?? a;
        final nameB = _appNames[b] ?? b;
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });

    final query = _searchQuery.trim().toLowerCase();
    final filteredPackages = allPackages.where((pkg) {
      final label = _appNames[pkg] ?? pkg;
      final labelLc = label.toLowerCase();
      final pkgLc = pkg.toLowerCase();

      final matchesSearch =
          query.isEmpty || labelLc.contains(query) || pkgLc.contains(query);
      if (!matchesSearch) return false;

      final categories = _permCategoriesByPkg[pkg] ?? {};

      if (_selectedCategories.isNotEmpty) {
        final hasSelectedCategory = _selectedCategories.any(
              (cat) => categories[cat] == true,
        );
        if (!hasSelectedCategory) return false;
      }

      if (_selectedRiskLevel != null) {
        final risk = _computeRiskLevel(categories);
        if (risk != _selectedRiskLevel) return false;
      }

      return true;
    }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search apps by name or package…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),

        // Permission filter chips
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: const Text('All permissions'),
                  selected: _selectedCategories.isEmpty,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategories.clear();
                    });
                  },
                ),
              ),
              ..._allCategories.map(
                    (cat) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(cat),
                    selected: _selectedCategories.contains(cat),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategories.add(cat);
                        } else {
                          _selectedCategories.remove(cat);
                        }
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Risk level filter chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('All risk levels'),
                  selected: _selectedRiskLevel == null,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedRiskLevel = null;
                      });
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Dangerous'),
                  selected: _selectedRiskLevel == 'Dangerous',
                  onSelected: (selected) {
                    setState(() {
                      _selectedRiskLevel = selected ? 'Dangerous' : null;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Moderate'),
                  selected: _selectedRiskLevel == 'Moderate',
                  onSelected: (selected) {
                    setState(() {
                      _selectedRiskLevel = selected ? 'Moderate' : null;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Safe'),
                  selected: _selectedRiskLevel == 'Safe',
                  onSelected: (selected) {
                    setState(() {
                      _selectedRiskLevel = selected ? 'Safe' : null;
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        Expanded(
          child: filteredPackages.isEmpty
              ? const Center(
            child: Text(
              'No apps match the current search/filters.',
              textAlign: TextAlign.center,
            ),
          )
              : ListView.builder(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: filteredPackages.length,
            itemBuilder: (context, index) {
              final pkg = filteredPackages[index];
              final label = _appNames[pkg] ?? pkg;
              final categories = _permCategoriesByPkg[pkg] ?? {};
              final risk = _computeRiskLevel(categories);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      label.isNotEmpty ? label[0].toUpperCase() : '?',
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(label)),
                      const SizedBox(width: 6),
                      _buildRiskBadge(risk),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      _buildPermissionChips(categories),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Open app settings',
                    icon: const Icon(Icons.settings),
                    onPressed: () => _openAppSettings(pkg),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- TAB 3: APK SCANNER ----------

  Widget _buildApkTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _pickAndAnalyzeApk,
            icon: const Icon(Icons.file_open),
            label: const Text('Pick APK file'),
          ),
          const SizedBox(height: 12),
          if (_apkAnalyzing) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          if (_apkName == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Pick an APK to see its permissions and safety level.\n'
                      'Only install apps from sources you trust.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            child: Text(
                              _apkName!.isNotEmpty
                                  ? _apkName![0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _apkName ?? '',
                              style:
                              Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_apkRisk != null) _buildRiskBadge(_apkRisk!),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _apkPackage ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Requested permissions',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      _buildPermissionChips(_apkCategories),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _installAnalyzedApk,
                        icon: const Icon(Icons.install_mobile),
                        label: const Text('Install APK'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Small pill showing "Dangerous", "Moderate", or "Safe"
  Widget _buildRiskBadge(String risk) {
    Color bg;
    Color fg;

    switch (risk) {
      case 'Dangerous':
        bg = Colors.red.withOpacity(0.15);
        fg = Colors.redAccent;
        break;
      case 'Moderate':
        bg = Colors.orange.withOpacity(0.15);
        fg = Colors.orangeAccent;
        break;
      default:
        bg = Colors.green.withOpacity(0.15);
        fg = Colors.greenAccent;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        risk,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Centralized permission chip UI so all tabs look the same
  Widget _buildPermissionChips(Map<String, bool> categories) {
    if (categories.isEmpty) {
      return const Text(
        'No sensitive permissions found',
        style: TextStyle(fontSize: 12),
      );
    }

    final chips = categories.entries
        .where((e) => e.value)
        .map(
          (e) => Chip(
        label: Text(
          e.key,
          style: const TextStyle(fontSize: 12),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    )
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}
