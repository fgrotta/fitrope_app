import 'dart:math';

String randomId() {
  const String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  Random random = Random();

  return List.generate(32, (index) => chars[random.nextInt(chars.length)]).join();
}