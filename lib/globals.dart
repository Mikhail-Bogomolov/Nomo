// globals.dart

// Переменные для хранения последнего состояния
String lastReceivedTime = '00:00';
bool lastReceivedIsWorkMode = true;

// Callback, который будет установлен в MiniTimerWindow для обновления его UI
typedef UpdateCallback = void Function(String time, bool isWorkMode);
UpdateCallback? updateCallback;

