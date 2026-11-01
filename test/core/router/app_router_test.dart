import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<GoRoute> allRoutes(List<RouteBase> routes) => [
    for (final route in routes) ...[
      if (route is GoRoute) route,
      ...allRoutes(route.routes),
    ],
  ];

  test('every route has a unique name (its analytics screen name)', () {
    final routes = allRoutes(appRouter.configuration.routes);
    expect(routes, isNotEmpty);
    final names = [for (final route in routes) route.name];
    expect(names, everyElement(isNotNull), reason: 'add name: to each GoRoute');
    expect(names.toSet().length, names.length, reason: 'names must be unique');
    for (final name in names) {
      expect(name, matches(RegExp(r'^[a-z][a-z0-9_]*$')), reason: '');
    }
  });
}
