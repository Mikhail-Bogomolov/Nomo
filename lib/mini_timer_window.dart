import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'globals.dart' as globals;




class MiniTimerApp extends StatelessWidget {
  const MiniTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MiniTimerWindow(),
    );
  }
}

class MiniTimerWindow extends StatefulWidget {
  const MiniTimerWindow({super.key});

  @override
  State<MiniTimerWindow> createState() => _MiniTimerWindowState();
}

class _MiniTimerWindowState extends State<MiniTimerWindow> with WindowListener {
  String time = globals.lastReceivedTime;
  bool isWorkMode = globals.lastReceivedIsWorkMode;

  @override
  void initState() {
    super.initState();
    _initWindow();

    globals.updateCallback = (String t, bool m) {
      if (mounted) {
        setState(() {
          time = t;
          isWorkMode = m;
        });
      }
    };
  }

  Future<void> _initWindow() async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      
      // Устанавливаем окно поверх всех других окон
      await windowManager.setAlwaysOnTop(true);
      
      // Периодически обновляем always on top, чтобы окно оставалось поверх
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        windowManager.setAlwaysOnTop(true).catchError((e) {
          timer.cancel();
        });
      });
    } catch (e) {
      // Если window_manager не доступен в мини-окне, игнорируем ошибку
      // Это нормально для DesktopMultiWindow
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowBlur() {
    // Когда окно теряет фокус, восстанавливаем always on top
    windowManager.setAlwaysOnTop(true).catchError((e) {
      // Игнорируем ошибки
    });
  }

  @override
  void onWindowFocus() {
    // Когда окно получает фокус, убеждаемся что оно поверх
    windowManager.setAlwaysOnTop(true).catchError((e) {
      // Игнорируем ошибки
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = isWorkMode ? Colors.orange : Colors.green;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Text(
          time,
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
