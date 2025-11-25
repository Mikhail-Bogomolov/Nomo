import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;

// Цвета и длительности
const Color workColor = Color(0xFFF59E0B);
const Color workBgColor = Color(0xFFFEF6EB);
const Color breakColor = Color(0xFF10B981);
const Color breakBgColor = Color(0xFFF0FDF4);

const int workDurationSeconds = 25 * 60;
const int breakDurationSeconds = 5 * 60;

// Типы активностей
enum ActivityType { notes, music, humor, relaxation }

void main() {
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

class _TimerHomePageState extends State<TimerHomePage> with TickerProviderStateMixin {
  Timer? _timer;
  int _currentSeconds = 25 * 60;
  bool _isWorkMode = true;
  bool _isPaused = true;
  bool _isInActivity = false;
  ActivityType? _currentActivity;

  // Настройки длительности (динамические)
  int _workMinutes = 25;
  int _breakMinutes = 5;

  // Геттеры для актуальной длительности (в секундах)
  int get workDurationSeconds => _workMinutes * 60;
  int get breakDurationSeconds => _breakMinutes * 60;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
      _resetTimer();
    });
  }

  // --- Управление активностями ---
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

  // --- Вспомогательные функции ---
  String _formatTime() {
    final minutes = (_currentSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_currentSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double _getProgress() {
    final totalDuration = _isWorkMode ? workDurationSeconds : breakDurationSeconds;
    return (totalDuration - _currentSeconds) / totalDuration;
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
          // Лого и настройки — только на главном экране
          if (!_isInActivity)
            Positioned(
              top: 30,
              left: 40,
              right: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nomo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  Icon(Icons.settings, color: primaryColor.withOpacity(0.6)),
                ],
              ),
            ),

          // Мини-таймер в правом верхнем углу — только при активности
          if (_isInActivity)
            Positioned(
              top: 30,
              right: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _formatTime(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ),

          // Основной контент по центру
          Center(
            child: _isInActivity
                ? _buildActivityContent()
                : _buildMainTimerScreen(primaryColor),
          ),

          // Карточки активностей — только в перерыве и не в активности
          if (!_isWorkMode && !_isInActivity) _buildActivityCards(primaryColor),
        ],
      ),
    );
  }

  // Главный экран: таймер + настройки + кнопки
  Widget _buildMainTimerScreen(Color primaryColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTimerCircle(primaryColor),
        const SizedBox(height: 20),
        _buildTimeSettings(primaryColor),
        const SizedBox(height: 20),
        _buildControls(primaryColor),
      ],
    );
  }

  // Панель настройки длительности
  Widget _buildTimeSettings(Color primaryColor) {
    return AnimatedOpacity(
      opacity: _isWorkMode ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 300),
      child: Column(
        children: [
          _TimeSettingRow(
            label: 'Работа',
            minutes: _workMinutes,
            onIncrease: () => setState(() => _workMinutes = (_workMinutes < 60) ? _workMinutes + 5 : 60),
            onDecrease: () => setState(() => _workMinutes = (_workMinutes > 5) ? _workMinutes - 5 : 5),
            isActive: _isWorkMode,
            color: primaryColor,
          ),
          const SizedBox(height: 12),
          _TimeSettingRow(
            label: 'Перерыв',
            minutes: _breakMinutes,
            onIncrease: () => setState(() => _breakMinutes = (_breakMinutes < 30) ? _breakMinutes + 1 : 30),
            onDecrease: () => setState(() => _breakMinutes = (_breakMinutes > 1) ? _breakMinutes - 1 : 1),
            isActive: !_isWorkMode,
            color: primaryColor,
          ),
        ],
      ),
    );
  }

  // Круглый таймер
  Widget _buildTimerCircle(Color primaryColor) {
    return GestureDetector(
      onTap: _togglePause,
      child: SizedBox(
        width: 300,
        height: 300,
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
                      fontSize: 80,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  if (_isPaused)
                    Text(
                      'ПАУЗА',
                      style: TextStyle(
                        fontSize: 16,
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
    );
  }

  // Кнопки управления
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
        const SizedBox(width: 40),
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

  // Карточки активностей
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
            left: i.isEven ? size.width * 0.1 : null,
            right: i.isOdd ? size.width * 0.1 : null,
            top: i < 2 ? size.height * 0.25 : null,
            bottom: i >= 2 ? size.height * 0.25 : null,
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

  // Контент активности (заметки, музыка и т.д.)
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

// Карточка с flip-анимацией при нажатии
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

class _ActivityCardState extends State<_ActivityCard> with SingleTickerProviderStateMixin {
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
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    )..addListener(() {
        if (_flipAnimation.value >= 0.5 && !_isFlipped) {
          setState(() {
            _isFlipped = true;
          });
        } else if (_flipAnimation.value < 0.5 && _isFlipped) {
          setState(() {
            _isFlipped = false;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_controller.isCompleted) {
      _controller.reverse();
    } else {
      _controller.forward().then((_) {
        widget.onTap(); // После анимации — переход в активность
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * math.pi;
          final isBackVisible = angle > math.pi / 2 && angle <= 3 * math.pi / 2;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // Отключает clipping при 3D-трансформации
              ..rotateY(angle),
            child: isBackVisible
                ? _buildBackSide()
                : _buildFrontSide(),
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
    final buttonColor = isActive ? color : color.withOpacity(0.3);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label:', style: TextStyle(color: textColor, fontSize: 16)),
        const SizedBox(width: 12),
        IconButton(
          onPressed: onDecrease,
          icon: Icon(Icons.remove, color: buttonColor),
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
          icon: Icon(Icons.add, color: buttonColor),
          splashRadius: 20,
        ),
      ],
    );
  }
}

// Экран "Заметки"
class NotesActivityScreen extends StatelessWidget {
  final VoidCallback onBack;

  const NotesActivityScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(
      title: 'Заметки',
      onBack: onBack,
      child: TextField(
        maxLines: null,
        expands: true,
        decoration: InputDecoration(
          hintText: 'Запишите свои мысли...',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}

// Новые экраны для остальных активностей:
class MusicActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const MusicActivityScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(
      title: 'Музыка',
      onBack: onBack,
      child: const Center(
        child: Text(
          '🎵 Подборка спокойной музыки\nскоро появится',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

class HumorActivityScreen extends StatelessWidget {
  final VoidCallback onBack;
  const HumorActivityScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return BaseActivityScreen(
      title: 'Юмор',
      onBack: onBack,
      child: const Center(
        child: Text(
          '😄 Анекдоты и мемы\nв разработке',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
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