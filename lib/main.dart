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
  int _currentSeconds = workDurationSeconds;
  bool _isWorkMode = true;
  bool _isPaused = true;
  bool _isInActivity = false; // Новое состояние: показываем ли активность?
  ActivityType? _currentActivity;

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

  // --- Форматирование и прогресс ---
  String _formatTime() {
    final minutes = (_currentSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_currentSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double _getProgress() {
    final totalDuration = _isWorkMode ? workDurationSeconds : breakDurationSeconds;
    return (totalDuration - _currentSeconds) / totalDuration;
  }

  // --- Сборка интерфейса ---
  @override
  Widget build(BuildContext context) {
    final Color primaryColor = _isWorkMode ? workColor : breakColor;
    final Color bgColor = _isWorkMode ? workBgColor : breakBgColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Лого и настройки (всегда видны, кроме активности)
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

          // Если в активности — показываем экран активности и таймер в углу
          if (_isInActivity)
            ..._buildActivityScreen(primaryColor),

          // Главный экран (таймер + карточки)
          if (!_isInActivity)
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Таймер
                _buildTimerCircle(primaryColor),
                const SizedBox(height: 30),
                // Контролы
                _buildControls(primaryColor),
              ],
            ),

          // Карточки (только в режиме перерыва)
          if (!_isWorkMode && !_isInActivity) _buildActivityCards(primaryColor),
        ],
      ),
    );
  }

  // Экран активности + таймер в правом верхнем углу
  List<Widget> _buildActivityScreen(Color primaryColor) {
    return [
      // Таймер в правом верхнем углу
      Positioned(
        top: 30,
        right: 40,
        child: GestureDetector(
          onTap: () {
            // По клику — выходим из активности
            _exitActivity();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
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
      ),

      // Сам экран активности
      Center(
        child: switch (_currentActivity) {
          ActivityType.notes => NotesActivityScreen(onBack: _exitActivity),
          ActivityType.music ||
          ActivityType.humor ||
          ActivityType.relaxation =>
            const Center(child: Text('Эта активность пока пустая')),
          null => const SizedBox(),
        },
      ),
    ];
  }

  // Таймер-круг
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

  // Контролы
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

  // Карточки активностей с flip-анимацией
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

// Экран "Заметки"
class NotesActivityScreen extends StatelessWidget {
  final VoidCallback onBack;

  const NotesActivityScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Заметки',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: TextField(
              maxLines: null,
              expands: true,
              decoration: InputDecoration(
                hintText: 'Запишите свои мысли...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Назад'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}