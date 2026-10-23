import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/karma_service.dart';

void main() {
  group('KarmaService.getLevel', () {
    test('karma negativo y bajo es Novato', () {
      expect(KarmaService.getLevel(-50).title, 'Novato');
      expect(KarmaService.getLevel(0).title, 'Novato');
      expect(KarmaService.getLevel(9).title, 'Novato');
    });

    test('10-29 es Explorador', () {
      expect(KarmaService.getLevel(10).title, 'Explorador');
      expect(KarmaService.getLevel(29).title, 'Explorador');
    });

    test('30-59 es Guardián', () {
      expect(KarmaService.getLevel(30).title, 'Guardián');
      expect(KarmaService.getLevel(59).title, 'Guardián');
    });

    test('60-99 es Héroe', () {
      expect(KarmaService.getLevel(60).title, 'Héroe');
      expect(KarmaService.getLevel(99).title, 'Héroe');
    });

    test('100 o más es Leyenda', () {
      expect(KarmaService.getLevel(100).title, 'Leyenda');
      expect(KarmaService.getLevel(99999).title, 'Leyenda');
    });
  });

  group('KarmaService.getLevelProgress', () {
    test('el nivel máximo (Leyenda) siempre está al 100%', () {
      expect(KarmaService.getLevelProgress(100), 1.0);
      expect(KarmaService.getLevelProgress(500), 1.0);
    });

    test('progreso al inicio de un nivel es ~0', () {
      // Explorador empieza en 10
      expect(KarmaService.getLevelProgress(10), closeTo(0.05, 0.05));
    });

    test('el progreso siempre está entre 0 y 1', () {
      for (final k in [-100, 0, 15, 45, 80, 100, 1000]) {
        final p = KarmaService.getLevelProgress(k);
        expect(p, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('KarmaService.levels', () {
    test('hay 5 niveles definidos', () {
      expect(KarmaService.levels.length, 5);
    });

    test('los niveles están ordenados por minKarma ascendente', () {
      for (var i = 1; i < KarmaService.levels.length; i++) {
        expect(
          KarmaService.levels[i].minKarma >
              KarmaService.levels[i - 1].minKarma,
          isTrue,
        );
      }
    });
  });

  group('KarmaService.computeKarma', () {
    test('suma votos positivos y resta negativos', () {
      expect(
        KarmaService.computeKarma([
          {'votes_up': 5, 'votes_down': 1},
          {'votes_up': 2, 'votes_down': 3},
        ]),
        3,
      );
    });

    test('sin alertas o con votos nulos es 0', () {
      expect(KarmaService.computeKarma([]), 0);
      expect(
        KarmaService.computeKarma([
          {'votes_up': null, 'votes_down': null},
        ]),
        0,
      );
    });
  });

  group('KarmaService ranking de ciclistas', () {
    final alerts = <Map<String, dynamic>>[
      {'user_id': 'a', 'user_name': 'Ana', 'votes_up': 4, 'votes_down': 1},
      {'user_id': 'b', 'user_name': 'Beto', 'votes_up': 10, 'votes_down': 0},
      {'user_id': 'a', 'user_name': 'Ana', 'votes_up': 2, 'votes_down': 0},
      {'user_id': '', 'votes_up': 50, 'votes_down': 0},
      {'user_id': 'c', 'votes_up': 0, 'votes_down': 2},
    ];

    test('agrupa por usuario sumando karma y alertas', () {
      final byUser = KarmaService.groupAlertsByUser(alerts);
      expect(byUser.keys, unorderedEquals(['a', 'b', 'c']));
      expect(byUser['a']!['karma'], 5);
      expect(byUser['a']!['alerts_count'], 2);
      expect(byUser['c']!['user_name'], 'Usuario');
    });

    test('completa con datos del perfil', () {
      final byUser = KarmaService.groupAlertsByUser(alerts);
      KarmaService.mergeProfiles(byUser, [
        {'id': 'a', 'username': 'ana_bici', 'avatar_url': 'x.png'},
        {'id': 'zz', 'username': 'no_existe'},
      ]);
      expect(byUser['a']!['username'], 'ana_bici');
      expect(byUser['a']!['full_name'], '');
      expect(byUser['a']!['avatar_url'], 'x.png');
      expect(byUser.containsKey('zz'), isFalse);
    });

    test('ordena por karma y respeta el límite', () {
      final byUser = KarmaService.groupAlertsByUser(alerts);
      final top = KarmaService.rankByKarma(byUser.values, 2);
      expect(top.map((u) => u['user_id']), ['b', 'a']);
    });
  });

  group('KarmaService ranking por comunas', () {
    test('suma km y ciclistas por comuna', () {
      final byCommune = KarmaService.groupProfilesByCommune([
        {'commune': 'Maipú', 'total_km': 10},
        {'commune': ' Maipú ', 'total_km': 5.5},
        {'commune': 'Ñuñoa', 'total_km': null},
        {'commune': '', 'total_km': 99},
        {'commune': null},
      ]);
      expect(byCommune.keys, unorderedEquals(['Maipú', 'Ñuñoa']));
      expect(byCommune['Maipú']!['total_km'], 15.5);
      expect(byCommune['Maipú']!['cyclists_count'], 2);
      expect(byCommune['Ñuñoa']!['total_km'], 0.0);
    });

    test('respaldo por ubicación ignora nombres vacíos', () {
      final byLoc = KarmaService.groupAlertsByLocation([
        {'location_name': 'Providencia'},
        {'location_name': 'Providencia'},
        {'location_name': 'Ubicación sin nombre'},
        {'location_name': '  '},
        {'location_name': null},
      ]);
      expect(byLoc.keys, ['Providencia']);
      expect(byLoc['Providencia']!['alerts_count'], 2);
    });

    test('ordena las comunas por km de mayor a menor', () {
      final sorted = KarmaService.sortByKm([
        {'commune': 'A', 'total_km': 3.0},
        {'commune': 'B', 'total_km': 12.0},
        {'commune': 'C', 'total_km': 7.0},
      ]);
      expect(sorted.map((c) => c['commune']), ['B', 'C', 'A']);
    });
  });
}
