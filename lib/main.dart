import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'mini_timer_window.dart';
import 'globals.dart' as globals;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';

// Цвета и длительности
const Color workColor = Color(0xFFF59E0B);
const Color workBgColor = Color(0xFFFEF6EB);
const Color breakColor = Color(0xFF10B981);
const Color breakBgColor = Color(0xFFF0FDF4);

// Типы активностей
enum ActivityType { notes, music, humor, relaxation }

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isMiniWindow = false;
  for (final arg in args) {
    if (arg == 'mini') {
      isMiniWindow = true;
      break;
    }
    try {
      final parsed = jsonDecode(arg);
      if (parsed is Map && parsed['args'] is List) {
        final argsList = parsed['args'] as List;
        if (argsList.contains('mini')) {
          isMiniWindow = true;
          break;
        }
      }
    } catch (e) {
      // Если не JSON — просто пропускаем
    }
  }

  if (isMiniWindow) {
    _initMiniWindowHandler();
    // Для мини-окна иконка наследуется от основного приложения
    // или устанавливается через нативные настройки платформы
    runApp(const MiniTimerApp());
    return;
  }

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1100, 750),
    minimumSize: Size(1100, 750),
    maximumSize: Size.infinite,
    center: true,
    title: "Nomo Timer",
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Иконка установлена через нативные ресурсы Windows (app_icon.ico)
  // Если нужно установить иконку программно, используйте ICO файл:
  // try {
  //   final appDir = await getApplicationSupportDirectory();
  //   final logoFile = File('${appDir.path}/logo/logo.ico');
  //   if (await logoFile.exists()) {
  //     await windowManager.setIcon(logoFile.path);
  //   }
  // } catch (e) {
  //   print('Ошибка установки иконки: $e');
  // }

  // Дополнительно устанавливаем минимальный размер и разрешаем изменение размера
  await windowManager.setMinimumSize(const Size(1100, 750));
  // Явно разрешаем изменение размера окна (максимальный размер уже установлен как infinite в WindowOptions)
  await windowManager.setResizable(true);

  runApp(const NomoTimerApp());
}

void _initMiniWindowHandler() {
  DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    if (call.method == 'update') {
      final data = jsonDecode(call.arguments);
      globals.lastReceivedTime = data['time'] ?? '00:00';
      globals.lastReceivedIsWorkMode = data['isWorkMode'] ?? true;
      globals.updateCallback?.call(
        globals.lastReceivedTime,
        globals.lastReceivedIsWorkMode,
      );
    } else if (call.method == 'setAlwaysOnTop') {
      // Обработчик для установки always on top (если нужен)
      // Реальная установка происходит в мини-окне через window_manager
    }
  });
}

class NomoTimerApp extends StatelessWidget {
  const NomoTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nomo Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Segoe UI'),
      home: const TimerHomePage(),
    );
  }
}

class TimerHomePage extends StatefulWidget {
  const TimerHomePage({super.key});

  @override
  State<TimerHomePage> createState() => _TimerHomePageState();
}

class _TimerHomePageState extends State<TimerHomePage>
    with TickerProviderStateMixin, WindowListener {
  Timer? _timer;
  int _currentSeconds = 25 * 60;
  bool _isWorkMode = true;
  bool _isPaused = true;
  bool _isInActivity = false;
  ActivityType? _currentActivity;
  WindowController? _miniWindow;
  final List<Note> _notes = [];
  final AudioPlayer _notificationPlayer = AudioPlayer();

  void _sendStateToMiniWindow() {
    if (_miniWindow == null) {
      return;
    }

    // Проверим, живо ли окно (опционально)
    try {
      final int miniWindowId = _miniWindow!.windowId;

      final data = jsonEncode({
        'time': _formatTime(),
        'isWorkMode': _isWorkMode,
        'isPaused': _isPaused,
      });

      // Вызываем асинхронно и обрабатываем ошибки
      DesktopMultiWindow.invokeMethod(miniWindowId, 'update', data).catchError((error) {
        // Если окно не найдено или закрыто, обнуляем ссылку
        if (mounted) {
          setState(() {
            _miniWindow = null;
          });
        }
      });
    } catch (e) {
      // Если произошла ошибка при подготовке данных, обнуляем окно
      if (mounted) {
        setState(() {
          _miniWindow = null;
        });
      }
    }
  }

  // контроллеры для добавления задач
  final TextEditingController _taskTitleController = TextEditingController();
  final TextEditingController _taskDurationController = TextEditingController();

  bool _isTasksPanelVisible = false;
  final List<Task> _tasks = [];

  // Настройки длительности (динамические)
  int _workMinutes = 25;
  int _breakMinutes = 5;

  // Геттеры для актуальной длительности (в секундах)
  int get workDurationSeconds => _workMinutes * 60;
  int get breakDurationSeconds => _breakMinutes * 60;

  @override
  void initState() {
    super.initState();
    _currentSeconds = workDurationSeconds;
    windowManager.addListener(this);
    _copyAssetsToAppDir();
  }

  Future<void> _copyAssetsToAppDir() async {
    final appDir = await getApplicationSupportDirectory();
    final audioDir = Directory('${appDir.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create();
    }

    // Используем те же имена треков, что и в MusicActivityScreen
    const trackNames = [
      'track1.mp3',
      'track2.mp3',
      'track3.mp3',
      'track4.mp3',
      'track5.mp3',
    ];

    for (final track in trackNames) {
      final assetPath = 'assets/audio/$track';
      final file = File('${audioDir.path}/$track');
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }

    // Копируем звуки оповещения (если они есть в assets)
    const notificationSounds = [
      'work_complete.mp3',
      'break_complete.mp3',
    ];

    for (final sound in notificationSounds) {
      try {
        final assetPath = 'assets/audio/$sound';
        final file = File('${audioDir.path}/$sound');
        if (!await file.exists()) {
          final data = await rootBundle.load(assetPath);
          await file.writeAsBytes(data.buffer.asUint8List());
        }
      } catch (e) {
        // Если файл не найден, пропускаем (звуки оповещения опциональны)
      }
    }
  }

  Future<void> _playNotificationSound(bool isWorkComplete) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final soundFile = File('${appDir.path}/audio/${isWorkComplete ? 'work_complete.mp3' : 'break_complete.mp3'}');
      
      if (await soundFile.exists()) {
        await _notificationPlayer.stop();
        await _notificationPlayer.setSource(DeviceFileSource(soundFile.path));
        await _notificationPlayer.setReleaseMode(ReleaseMode.release);
        await _notificationPlayer.resume();
      } else {
        // Если файл не найден, используем системный звук или просто игнорируем
        // Можно добавить fallback на системный звук
      }
    } catch (e) {
      // Игнорируем ошибки воспроизведения звука
      print('Ошибка воспроизведения звука оповещения: $e');
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    _miniWindow?.close();
    _notificationPlayer.dispose();
    _taskTitleController.dispose();
    _taskDurationController.dispose();
    super.dispose();
  }

  @override
  void onWindowMinimize() async {
    _miniWindow = await DesktopMultiWindow.createWindow(
      jsonEncode({
        'args': ['mini'],
      }), // <--- Вернули как было
    );
  }

  // Добавьте метод, который будет вызываться при закрытии мини-окна
  void _onMiniWindowClosed() {
    print('--- Мини-окно закрыто ---');
    _miniWindow = null; // <--- Обнуляем
  }

  @override
  void onWindowRestore() async {
    await windowManager.show();
  }

  @override
  Future<bool> onWindowClose() async {
    // Закрываем мини-окно перед закрытием основного
    if (_miniWindow != null) {
      try {
        await _miniWindow!.close();
        _miniWindow = null;
      } catch (e) {
        // Игнорируем ошибки при закрытии мини-окна
        _miniWindow = null;
      }
    }
    // Разрешаем закрытие основного окна
    return true;
  }

  // --- Управление временем и настройками ---

  void _updateWorkTime(int delta) {
    setState(() {
      int newTime = _workMinutes + delta;
      if (newTime < 5) newTime = 5;
      if (newTime > 120) newTime = 120;

      _workMinutes = newTime;

      if (_isWorkMode) {
        _currentSeconds = workDurationSeconds;
        _sendStateToMiniWindow();
      }
    });
  }

  void _updateBreakTime(int delta) {
    setState(() {
      int newTime = _breakMinutes + delta;
      if (newTime < 1) newTime = 1;
      if (newTime > 60) newTime = 60;

      _breakMinutes = newTime;

      if (!_isWorkMode) {
        _currentSeconds = breakDurationSeconds;
        _sendStateToMiniWindow();
      }
    });
  }

  // --- Управление таймером ---
  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _timer?.cancel();
      } else {
        _startTimerTick();
      }
    });
    _sendStateToMiniWindow();
  }

  void _startTimerTick() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentSeconds > 0) {
        setState(() {
          _currentSeconds--;
        });
        _sendStateToMiniWindow();
      } else {
        _timer?.cancel();
        _switchMode(playSound: true); // Автоматическое завершение - воспроизводим звук
      }
    });
  }

  void _resetTimer() {
    setState(() {
      _isPaused = true;
      _timer?.cancel();
      _currentSeconds = _isWorkMode
          ? workDurationSeconds
          : breakDurationSeconds;
    });
    _sendStateToMiniWindow();
  }

  void _switchMode({bool playSound = false}) {
    // Определяем, какой режим закончился (до переключения)
    final wasWorkMode = _isWorkMode;
    
    setState(() {
      _isWorkMode = !_isWorkMode;
      _isPaused = true;
      _timer?.cancel();
      _currentSeconds = _isWorkMode
          ? workDurationSeconds
          : breakDurationSeconds;
    });
    
    // Воспроизводим звук оповещения только при автоматическом завершении таймера
    if (playSound) {
      _playNotificationSound(wasWorkMode);
    }
    
    _sendStateToMiniWindow();
  }

  // --- Вспомогательные функции ---
  String _formatTime() {
    final minutes = (_currentSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_currentSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double _getProgress() {
    final totalDuration = _isWorkMode
        ? workDurationSeconds
        : breakDurationSeconds;
    if (totalDuration == 0) return 0.0;
    return (totalDuration - _currentSeconds) / totalDuration;
  }

  void _enterActivity(ActivityType type) {
    setState(() {
      _isInActivity = true;
      _currentActivity = type;
    });
  }

  void _exitActivity() {
    setState(() {
      _isInActivity = false;
      _currentActivity = null;
    });
  }

  // --- Задачи ---
  void _addTask() {
    final title = _taskTitleController.text.trim();
    final minutes = int.tryParse(_taskDurationController.text.trim()) ?? 0;

    if (title.isEmpty || minutes <= 0) return;

    setState(() {
      _tasks.add(Task(title: title, durationMinutes: minutes));
    });

    _taskTitleController.clear();
    _taskDurationController.clear();
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _toggleTaskCompletion(int index) {
    setState(() {
      _tasks[index].isCompleted = !_tasks[index].isCompleted;
    });
  }

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
  }

  int get totalTaskDuration =>
      _tasks.fold(0, (sum, task) => sum + task.durationMinutes);

  // --- UI строители (оставлены без изменений) ---

  Widget _buildTasksPanel(Color primaryColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isTasksPanelVisible ? 320 : 0,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        border: Border(left: BorderSide(color: primaryColor.withOpacity(0.2))),
      ),
      child: OverflowBox(
        minWidth: 0,
        maxWidth: 320,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          child: _isTasksPanelVisible
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Задачи',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () =>
                                setState(() => _isTasksPanelVisible = false),
                            icon: Icon(Icons.close, color: primaryColor),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.grey),
                    Expanded(
                      child: _tasks.isEmpty
                          ? Center(
                              child: Text(
                                'Пока нет задач',
                                style: TextStyle(
                                  color: primaryColor.withOpacity(0.7),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              itemCount: _tasks.length,
                              itemBuilder: (context, index) {
                                final task = _tasks[index];
                                return ListTile(
                                  leading: Checkbox(
                                    value: task.isCompleted,
                                    onChanged: (_) =>
                                        _toggleTaskCompletion(index),
                                    activeColor: primaryColor,
                                  ),
                                  title: Text(task.title),
                                  subtitle: Text('${task.durationMinutes} мин'),
                                  trailing: IconButton(
                                    onPressed: () => _removeTask(index),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _taskTitleController,
                            decoration: const InputDecoration(
                              labelText: 'Название задачи',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _taskDurationController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Минуты',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _addTask,
                              child: const Text("Добавить задачу"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Всего: $totalTaskDuration мин',
                            style: TextStyle(color: primaryColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  // Главный экран
  Widget _buildMainTimerScreen(Color primaryColor) {
    return Column(
      children: [
        // 1. Верхняя шапка (Лого и настройки)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nomo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              Icon(Icons.settings, color: primaryColor.withOpacity(0.6)),
            ],
          ),
        ),

        // 2. Основная часть
        Expanded(
          child: Row(
            children: [
              // Центральная зона
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Таймер
                        _buildTimerCircleWithTaskButton(primaryColor),
                        const SizedBox(height: 25),
                        // Кнопки управления
                        _buildControls(primaryColor),
                        const SizedBox(height: 30),

                        if (_isPaused) ...[
                          _buildTimeSettings(primaryColor),
                          const SizedBox(height: 20),
                          // Кнопка сворачивания - теперь тут
                          FloatingActionButton(
                            onPressed: () async {
                              _miniWindow =
                                  await DesktopMultiWindow.createWindow(
                                    jsonEncode({
                                      'args': ['mini'],
                                    }),
                                  );
                              await _miniWindow!.setFrame(
                                const Rect.fromLTWH(100, 100, 300, 150),
                              );
                              await _miniWindow!.show();
                              // Пытаемся установить always on top через invokeMethod
                              try {
                                await DesktopMultiWindow.invokeMethod(
                                  _miniWindow!.windowId,
                                  'setAlwaysOnTop',
                                  'true',
                                );
                              } catch (e) {
                                // Игнорируем ошибку, если метод не поддерживается
                              }
                            },
                            backgroundColor: const Color.fromARGB(
                              255,
                              254,
                              246,
                              235,
                            ),
                            child: Icon(Icons.minimize),
                          ),
                        ] else ...[
                          const SizedBox(height: 90),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Панель задач
              _buildTasksPanel(primaryColor),
            ],
          ),
        ),
      ],
    );
  }

  // --- Сборка UI ---
  @override
  Widget build(BuildContext context) {
    final Color primaryColor = _isWorkMode ? workColor : breakColor;
    final Color bgColor = _isWorkMode ? workBgColor : breakBgColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          _isInActivity
              ? Center(child: _buildActivityContent())
              : _buildMainTimerScreen(primaryColor),

          if (!_isWorkMode && !_isInActivity && !_isTasksPanelVisible)
            _buildActivityCards(primaryColor),
        ],
      ),
    );
  }

  Widget _buildTimeSettings(Color primaryColor) {
    return Column(
      children: [
        _TimeSettingRow(
          label: 'Работа',
          minutes: _workMinutes,
          onIncrease: () => _updateWorkTime(5),
          onDecrease: () => _updateWorkTime(-5),
          isActive: _isWorkMode,
          color: primaryColor,
        ),
        const SizedBox(height: 12),
        _TimeSettingRow(
          label: 'Перерыв',
          minutes: _breakMinutes,
          onIncrease: () => _updateBreakTime(1),
          onDecrease: () => _updateBreakTime(-1),
          isActive: !_isWorkMode,
          color: primaryColor,
        ),
      ],
    );
  }

  Widget _buildTimerCircleWithTaskButton(Color primaryColor) {
    return SizedBox(
      width: 320,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: _togglePause,
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _getProgress(),
                    strokeWidth: 12,
                    backgroundColor: primaryColor.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(),
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                        if (_isPaused)
                          Text(
                            'ПАУЗА',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                              color: primaryColor.withOpacity(0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 0,
            right: 10,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(
                  () => _isTasksPanelVisible = !_isTasksPanelVisible,
                ),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.assignment, color: primaryColor, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(Color primaryColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _resetTimer,
          icon: Icon(Icons.refresh, color: primaryColor.withOpacity(0.7)),
          label: Text(
            'Сброс',
            style: TextStyle(
              color: primaryColor.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 24),
        TextButton.icon(
          onPressed: _switchMode,
          icon: Text(
            _isWorkMode ? 'На перерыв' : 'К работе',
            style: TextStyle(
              color: primaryColor.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          label: Icon(
            _isWorkMode ? Icons.arrow_forward : Icons.arrow_back,
            color: primaryColor.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCards(Color primaryColor) {
    final size = MediaQuery.of(context).size;

    final cards = [
      ('Заметки', ActivityType.notes, Icons.edit),
      ('Музыка', ActivityType.music, Icons.music_note),
      ('Юмор', ActivityType.humor, Icons.sentiment_satisfied),
      ('Релакс', ActivityType.relaxation, Icons.spa),
    ];

    return Stack(
      children: [
        for (int i = 0; i < cards.length; i++)
          Positioned(
            left: i.isEven ? size.width * 0.05 : null,
            right: i.isOdd ? size.width * 0.05 : null,
            top: i < 2 ? size.height * 0.2 : null,
            bottom: i >= 2 ? size.height * 0.2 : null,
            child: _ActivityCard(
              title: cards[i].$1,
              icon: cards[i].$3,
              type: cards[i].$2,
              color: primaryColor,
              onTap: () => _enterActivity(cards[i].$2),
            ),
          ),
      ],
    );
  }

  Widget _buildActivityContent() {
    return switch (_currentActivity) {
      ActivityType.notes => NotesActivityScreen(
        onBack: _exitActivity,
        notes: _notes, // <-- Передаём заметки
        onSaveNote: (title, content) {
          if (title.trim().isNotEmpty && content.trim().isNotEmpty) {
            setState(() {
              _notes.add(Note(title: title, content: content));
            });
          }
        },
      ),
      ActivityType.music => MusicActivityScreen(onBack: _exitActivity),
      ActivityType.humor => HumorActivityScreen(onBack: _exitActivity),
      ActivityType.relaxation => RelaxationActivityScreen(
        onBack: _exitActivity,
      ),
      null => const SizedBox(),
    };
  }
}

// --- Классы поддержки ---

class Task {
  final String title;
  final int durationMinutes;
  bool isCompleted;

  Task({
    required this.title,
    required this.durationMinutes,
    this.isCompleted = false,
  });
}

class _ActivityCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final ActivityType type;
  final Color color;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.title,
    required this.icon,
    required this.type,
    required this.color,
    required this.onTap,
  });
  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flipAnimation;
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _flipAnimation =
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        )..addListener(() {
          if (_flipAnimation.value >= 0.5 && !_isFlipped)
            setState(() => _isFlipped = true);
          else if (_flipAnimation.value < 0.5 && _isFlipped)
            setState(() => _isFlipped = false);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_controller.isCompleted)
          _controller.reverse();
        else
          _controller.forward().then((_) => widget.onTap());
      },
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * math.pi;
          final isBackVisible = angle > math.pi / 2 && angle <= 3 * math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isBackVisible ? _buildBackSide() : _buildFrontSide(),
          );
        },
      ),
    );
  }

  Widget _buildFrontSide() {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color.withOpacity(0.5), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 32, color: widget.color),
          const SizedBox(height: 8),
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackSide() {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color, width: 2),
      ),
      child: Center(
        child: Text(
          'Выбрать?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class BaseActivityScreen extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onBack;
  const BaseActivityScreen({
    super.key,
    required this.title,
    required this.child,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Назад', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade400,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeSettingRow extends StatelessWidget {
  final String label;
  final int minutes;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final bool isActive;
  final Color color;
  const _TimeSettingRow({
    required this.label,
    required this.minutes,
    required this.onIncrease,
    required this.onDecrease,
    required this.isActive,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isActive ? color : color.withOpacity(0.5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label:', style: TextStyle(color: textColor, fontSize: 16)),
        const SizedBox(width: 12),
        IconButton(
          onPressed: onDecrease,
          icon: Icon(
            Icons.remove,
            color: isActive ? color : color.withOpacity(0.3),
          ),
          splashRadius: 20,
        ),
        Container(
          width: 60,
          alignment: Alignment.center,
          child: Text(
            '$minutes мин',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
        IconButton(
          onPressed: onIncrease,
          icon: Icon(
            Icons.add,
            color: isActive ? color : color.withOpacity(0.3),
          ),
          splashRadius: 20,
        ),
      ],
    );
  }
}

class NotesActivityScreen extends StatefulWidget {
  final VoidCallback onBack;
  final List<Note> notes; // <-- Принимаем список заметок
  final Function(String, String) onSaveNote; // <-- Функция сохранения

  const NotesActivityScreen({
    super.key,
    required this.onBack,
    required this.notes,
    required this.onSaveNote,
  });

  @override
  State<NotesActivityScreen> createState() => _NotesActivityScreenState();
}

class _NotesActivityScreenState extends State<NotesActivityScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Заметки',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Поля для новой заметки
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Заголовок',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _contentController,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                labelText: 'Текст заметки',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  widget.onSaveNote(
                    _titleController.text,
                    _contentController.text,
                  );
                  _titleController.clear();
                  _contentController.clear();
                },
                icon: const Icon(Icons.save),
                label: const Text('Сохранить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade400,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Список сохранённых заметок
          const Text(
            'Сохранённые заметки:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: widget.notes.isEmpty
                ? const Center(child: Text('Пока нет заметок'))
                : ListView.builder(
                    itemCount: widget.notes.length,
                    itemBuilder: (context, index) {
                      final note = widget.notes[index];
                      return Card(
                        child: ListTile(
                          title: Text(note.title),
                          // Убираем subtitle с содержимым
                          onTap: () {
                            _titleController.text = note.title;
                            _contentController.text = note
                                .content; // <-- При клике подгружаем полный текст
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}

class MusicActivityScreen extends StatefulWidget {
  final VoidCallback onBack;
  const MusicActivityScreen({super.key, required this.onBack});

  @override
  State<MusicActivityScreen> createState() => _MusicActivityScreenState();
}

class HumorActivityScreen extends StatefulWidget {
  final VoidCallback onBack;
  const HumorActivityScreen({super.key, required this.onBack});

  @override
  State<HumorActivityScreen> createState() => _HumorActivityScreenState();
}

class _HumorActivityScreenState extends State<HumorActivityScreen> {
  final List<String> _imagePaths = [
    'assets/pictures/p1.png',
    'assets/pictures/p2.png',
    'assets/pictures/p3.png',
  ];
  
  late int _currentIndex;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    // Показываем рандомную картинку при открытии
    _currentIndex = _random.nextInt(_imagePaths.length);
  }

  void _nextImage() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % _imagePaths.length;
    });
  }

  void _previousImage() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + _imagePaths.length) % _imagePaths.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(
      title: 'Юмор',
      onBack: widget.onBack,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity! > 0) {
                    // Свайп вправо - предыдущая картинка
                    _previousImage();
                  } else if (details.primaryVelocity! < 0) {
                    // Свайп влево - следующая картинка
                    _nextImage();
                  }
                },
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 800,
                    maxHeight: 600,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      _imagePaths[_currentIndex],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          child: const Center(
                            child: Text(
                              'Ошибка загрузки изображения',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Кнопки навигации
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _previousImage,
                icon: const Icon(Icons.arrow_back_ios),
                iconSize: 32,
                color: Colors.orange.shade400,
                tooltip: 'Предыдущая',
              ),
              const SizedBox(width: 20),
              Text(
                '${_currentIndex + 1} / ${_imagePaths.length}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                onPressed: _nextImage,
                icon: const Icon(Icons.arrow_forward_ios),
                iconSize: 32,
                color: Colors.orange.shade400,
                tooltip: 'Следующая',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Свайп влево/вправо для навигации',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class RelaxationActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const RelaxationActivityScreen({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(
      title: 'Релакс',
      onBack: onBack,
      child: const Center(
        child: Text(
          '🧘 Дыхательные упражнения\nи визуализации — скоро',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

class Note {
  final String title;
  final String content;
  final DateTime timestamp;

  Note({required this.title, required this.content, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

class _MusicActivityScreenState extends State<MusicActivityScreen> {
  final AudioPlayer _player = AudioPlayer();
  int? _currentlyPlayingIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0; // Громкость от 0.0 до 1.0
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  // Используем имена файлов без префикса
  final List<String> _trackNames = [
    'track1.mp3',
    'track2.mp3',
    'track3.mp3',
    'track4.mp3',
    'track5.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _positionSubscription = _player.onPositionChanged.listen(
      (position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      },
      onError: (error) {
        // Игнорируем ошибки потока от плагина (известная проблема audioplayers)
      },
    );

    _durationSubscription = _player.onDurationChanged.listen(
      (duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      },
      onError: (error) {
        // Игнорируем ошибки потока от плагина (известная проблема audioplayers)
      },
    );

    _playerStateSubscription = _player.onPlayerStateChanged.listen(
      (state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      },
      onError: (error) {
        // Игнорируем ошибки потока от плагина (известная проблема audioplayers)
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _playTrack(int index) async {
    try {
      await _player.stop();
      // Получаем путь к директории assets/audio/
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/audio/${_trackNames[index]}');

      if (await file.exists()) {
        await _player.setSource(DeviceFileSource(file.path));
        await _player.setVolume(_volume); // Устанавливаем громкость
        await _player.resume();
        setState(() {
          _currentlyPlayingIndex = index;
          _isPlaying = true;
        });
      } else {
        print('Файл не найден: ${file.path}');
      }
    } catch (e) {
      print('Ошибка воспроизведения: $e');
    }
  }

  Future<void> _setVolume(double volume) async {
    setState(() {
      _volume = volume.clamp(0.0, 1.0);
    });
    await _player.setVolume(_volume);
  }

  Future<void> _pauseOrResume() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.setVolume(_volume); // Убеждаемся, что громкость установлена
      await _player.resume();
    }
  }

  Future<void> _playNext() async {
    if (_currentlyPlayingIndex != null) {
      final nextIndex = (_currentlyPlayingIndex! + 1) % _trackNames.length;
      await _playTrack(nextIndex);
    }
  }

  Future<void> _playPrevious() async {
    if (_currentlyPlayingIndex != null) {
      final prevIndex = (_currentlyPlayingIndex! - 1 + _trackNames.length) % _trackNames.length;
      await _playTrack(prevIndex);
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    setState(() {
      _currentlyPlayingIndex = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Музыка',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              itemCount: _trackNames.length,
              itemBuilder: (context, index) {
                final trackName = 'Трек ${index + 1}';
                final isPlaying = _currentlyPlayingIndex == index;

                return Card(
                  child: ListTile(
                    title: Text(trackName),
                    trailing: isPlaying
                        ? IconButton(
                            icon: const Icon(Icons.stop),
                            onPressed: _stopPlayback,
                          )
                        : IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _playTrack(index),
                          ),
                  ),
                );
              },
            ),
          ),

          // Панель управления воспроизведением
          if (_currentlyPlayingIndex != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  // Прогресс-бар
                  Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds.toDouble()
                        : 0.0,
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (value) async {
                      await _player.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                  // Время
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Кнопки управления
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 32,
                        onPressed: _currentlyPlayingIndex != null ? _playPrevious : null,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        iconSize: 40,
                        onPressed: _currentlyPlayingIndex != null ? _pauseOrResume : null,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 32,
                        onPressed: _currentlyPlayingIndex != null ? _playNext : null,
                        color: Colors.orange.shade400,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Регулятор громкости
                  Row(
                    children: [
                      Icon(
                        _volume == 0
                            ? Icons.volume_off
                            : _volume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                        color: Colors.orange.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          onChanged: _setVolume,
                          activeColor: Colors.orange.shade400,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(_volume * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Назад', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade400,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
