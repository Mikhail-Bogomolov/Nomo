import 'package:flutter/material.dart';

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

class _MiniTimerWindowState extends State<MiniTimerWindow> {
  String time = globals.lastReceivedTime;
  bool isWorkMode = globals.lastReceivedIsWorkMode;

  @override
  void initState() {
    super.initState();

    globals.updateCallback = (String t, bool m) {
      if (mounted) {
        setState(() {
          time = t;
          isWorkMode = m;
        });
      }
    };
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
