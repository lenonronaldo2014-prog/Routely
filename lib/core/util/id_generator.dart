import 'dart:math';

/// IDs locais para as paradas.
///
/// Timestamp + sufixo aleatório em vez de UUID: os IDs são gerados só neste
/// aparelho, então basta serem únicos localmente. O prefixo de tempo ainda dá
/// ordenação natural de brinde.
class IdGenerator {
  IdGenerator._();

  static final _random = Random();
  static const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  static String generate() {
    final timestamp =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36).padLeft(9, '0');
    final suffix = List.generate(
      6,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    return '$timestamp$suffix';
  }
}
