import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:window_manager/window_manager.dart';

// Цвета и длительности
const Color workColor = Color(0xFFF59E0B);
const Color workBgColor = Color(0xFFFEF6EB);
const Color breakColor = Color(0xFF10B981);
const Color breakBgColor = Color(0xFFF0FDF4);

// Типы активностей
enum ActivityType { notes, music, humor, relaxation }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const Size startSize = Size(1100, 750);

  WindowOptions windowOptions = const WindowOptions(
    size: startSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.setMinimumSize(const Size(1100, 750));
    await windowManager.setMaximumSize(Size(double.infinity, double.infinity));
    await windowManager.setResizable(false);
    await windowManager.setIgnoreMouseEvents(false);
    await windowManager.setAlwaysOnTop(false);
    Future.delayed(const Duration(milliseconds: 200), () async {
      await windowManager.setResizable(true);
    });
  });

  runApp(const NomoTimerApp());
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

class _TimerHomePageState extends State<TimerHomePage> with TickerProviderStateMixin, WindowListener {
  Timer? _timer;
  int _currentSeconds = 25 * 60;
  bool _isWorkMode = true;
  bool _isPaused = true;
  bool _isInActivity = false;
  ActivityType? _currentActivity;

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
    // При старте сразу ставим правильное время
    _currentSeconds = workDurationSeconds;
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    _taskTitleController.dispose();
    _taskDurationController.dispose();
    super.dispose();
  }

  @override
  void onWindowResize() async {
    const Size minSize = Size(1100, 750);
    final size = await windowManager.getSize();

    if (size.width < minSize.width || size.height < minSize.height) {
      await windowManager.setSize(minSize);
    }
  }


  // --- Управление временем и настройками ---

  // Логика обновления времени работы
  void _updateWorkTime(int delta) {
    setState(() {
      int newTime = _workMinutes + delta;
      // Ограничиваем от 5 до 60 (или больше) минут
      if (newTime < 5) newTime = 5;
      if (newTime > 120) newTime = 120;
      
      _workMinutes = newTime;

      // ВАЖНО: Если мы сейчас в режиме работы, сразу обновляем таймер на экране
      if (_isWorkMode) {
        _currentSeconds = workDurationSeconds;
      }
    });
  }

  // Логика обновления времени перерыва
  void _updateBreakTime(int delta) {
    setState(() {
      int newTime = _breakMinutes + delta;
      if (newTime < 1) newTime = 1;
      if (newTime > 60) newTime = 60;

      _breakMinutes = newTime;

      // ВАЖНО: Если мы сейчас в режиме перерыва, сразу обновляем таймер на экране
      if (!_isWorkMode) {
        _currentSeconds = breakDurationSeconds;
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
  }

  void _startTimerTick() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentSeconds > 0) {
        setState(() {
          _currentSeconds--;
        });
      } else {
        _timer?.cancel();
        _switchMode();
      }
    });
  }

  void _resetTimer() {
    setState(() {
      _isPaused = true;
      _timer?.cancel();
      _currentSeconds = _isWorkMode ? workDurationSeconds : breakDurationSeconds;
    });
  }

  void _switchMode() {
    setState(() {
      _isWorkMode = !_isWorkMode;
      _isPaused = true; // При смене режима встаем на паузу (по желанию)
      _timer?.cancel();
      _currentSeconds = _isWorkMode ? workDurationSeconds : breakDurationSeconds;
    });
  }

  // --- Вспомогательные функции ---
  String _formatTime() {
    final minutes = (_currentSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_currentSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double _getProgress() {
    final totalDuration = _isWorkMode ? workDurationSeconds : breakDurationSeconds;
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

  int get totalTaskDuration => _tasks.fold(0, (sum, task) => sum + task.durationMinutes);

  // --- UI строители ---

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
                            onPressed: () => setState(() => _isTasksPanelVisible = false),
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
                                style: TextStyle(color: primaryColor.withOpacity(0.7)),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              itemCount: _tasks.length,
                              itemBuilder: (context, index) {
                                final task = _tasks[index];
                                return ListTile(
                                  leading: Checkbox(
                                    value: task.isCompleted,
                                    onChanged: (_) => _toggleTaskCompletion(index),
                                    activeColor: primaryColor,
                                  ),
                                  title: Text(task.title),
                                  subtitle: Text('${task.durationMinutes} мин'),
                                  trailing: IconButton(
                                    onPressed: () => _removeTask(index),
                                    icon: Icon(Icons.delete_outline, color: Colors.grey[500]),
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
                          Text('Всего: $totalTaskDuration мин', style: TextStyle(color: primaryColor)),
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
                        
                        // ВАЖНО: Настройки показываем ТОЛЬКО если таймер на ПАУЗЕ
                        // Чтобы размер не прыгал, можно использовать Visibility с maintainSize: false
                        // или просто условный рендеринг.
                        if (_isPaused) ...[
                           _buildTimeSettings(primaryColor),
                        ] else ...[
                           // Пустое место, чтобы кнопки не скакали, или просто ничего, если хотим минимализм
                           // Если убрать SizedBox, контент поднимется выше. 
                           // Оставим SizedBox той же высоты, если нужно сохранять позицию,
                           // Но по твоему описанию "не нужно показывать", значит просто скрываем.
                           const SizedBox(height: 90), // Примерная высота настроек, чтобы верстка не прыгала
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

          if (!_isWorkMode && !_isInActivity) 
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
          // Вызываем новые методы, которые сразу обновляют таймер
          onIncrease: () => _updateWorkTime(5),
          onDecrease: () => _updateWorkTime(-5),
          isActive: _isWorkMode,
          color: primaryColor,
        ),
        const SizedBox(height: 12),
        _TimeSettingRow(
          label: 'Перерыв',
          minutes: _breakMinutes,
          // Вызываем новые методы
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
                onTap: () => setState(() => _isTasksPanelVisible = !_isTasksPanelVisible),
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
                      )
                    ],
                  ),
                  child: Icon(
                    Icons.assignment, 
                    color: primaryColor,
                    size: 24,
                  ),
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
            style: TextStyle(color: primaryColor.withOpacity(0.7), fontSize: 16),
          ),
        ),
        const SizedBox(width: 24),
        TextButton.icon(
          onPressed: _switchMode,
          icon: Text(
            _isWorkMode ? 'На перерыв' : 'К работе',
            style: TextStyle(color: primaryColor.withOpacity(0.7), fontSize: 16),
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
      ActivityType.notes => NotesActivityScreen(onBack: _exitActivity),
      ActivityType.music => MusicActivityScreen(onBack: _exitActivity),
      ActivityType.humor => HumorActivityScreen(onBack: _exitActivity),
      ActivityType.relaxation => RelaxationActivityScreen(onBack: _exitActivity),
      null => const SizedBox(),
    };
  }
}

// --- Классы поддержки ---

class Task {
  final String title;
  final int durationMinutes; 
  bool isCompleted;

  Task({required this.title, required this.durationMinutes, this.isCompleted = false});
}

class _ActivityCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final ActivityType type;
  final Color color;
  final VoidCallback onTap;

  const _ActivityCard({required this.title, required this.icon, required this.type, required this.color, required this.onTap});
  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flipAnimation;
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut))
      ..addListener(() {
        if (_flipAnimation.value >= 0.5 && !_isFlipped) setState(() => _isFlipped = true);
        else if (_flipAnimation.value < 0.5 && _isFlipped) setState(() => _isFlipped = false);
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
        if (_controller.isCompleted) _controller.reverse();
        else _controller.forward().then((_) => widget.onTap());
      },
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * math.pi;
          final isBackVisible = angle > math.pi / 2 && angle <= 3 * math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
            child: isBackVisible ? _buildBackSide() : _buildFrontSide(),
          );
        },
      ),
    );
  }

  Widget _buildFrontSide() {
    return Container(
      width: 180, height: 120,
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
          Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: widget.color)),
        ],
      ),
    );
  }

  Widget _buildBackSide() {
    return Container(
      width: 180, height: 120,
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color, width: 2),
      ),
      child: Center(child: Text('Выбрать?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.color))),
    );
  }
}

class BaseActivityScreen extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onBack;
  const BaseActivityScreen({super.key, required this.title, required this.child, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
  const _TimeSettingRow({required this.label, required this.minutes, required this.onIncrease, required this.onDecrease, required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = isActive ? color : color.withOpacity(0.5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label:', style: TextStyle(color: textColor, fontSize: 16)),
        const SizedBox(width: 12),
        IconButton(onPressed: onDecrease, icon: Icon(Icons.remove, color: isActive ? color : color.withOpacity(0.3)), splashRadius: 20),
        Container(width: 60, alignment: Alignment.center, child: Text('$minutes мин', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor))),
        IconButton(onPressed: onIncrease, icon: Icon(Icons.add, color: isActive ? color : color.withOpacity(0.3)), splashRadius: 20),
      ],
    );
  }
}

class NotesActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const NotesActivityScreen({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(
      title: 'Заметки', onBack: onBack,
      child: TextField(maxLines: null, expands: true, decoration: InputDecoration(hintText: 'Запишите свои мысли...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.all(16))),
    );
  }
}

class MusicActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const MusicActivityScreen({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(title: 'Музыка', onBack: onBack, child: const Center(child: Text('🎵 Подборка спокойной музыки\nскоро появится', textAlign: TextAlign.center, style: TextStyle(fontSize: 18))));
  }
}

class HumorActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const HumorActivityScreen({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(title: 'Юмор', onBack: onBack, child: const Center(child: Text('😄 Анекдоты и мемы\nв разработке', textAlign: TextAlign.center, style: TextStyle(fontSize: 18))));
  }
}

class RelaxationActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const RelaxationActivityScreen({super.key, required this.onBack});
  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(title: 'Релакс', onBack: onBack, child: const Center(child: Text('🧘 Дыхательные упражнения\nи визуализации — скоро', textAlign: TextAlign.center, style: TextStyle(fontSize: 18))));
  }
}