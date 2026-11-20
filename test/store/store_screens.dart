import 'package:gym_tracker/features/home/presentation/home_page.dart';
import 'package:flutter/widgets.dart';

/// The screens shown in the store screenshots, by name. Each one is built
/// with sample data, the way its widget test builds it (a view with fake
/// data, not a page that loads from the network). The names are the
/// `screen` values in `store/tools/shots.json`.
///
/// Only list screens of features that are live for every user in prod
/// (check the feature flags): store images must show the real app.
final Map<String, Widget Function()> storeScreens = {
  'home': () => const HomePage(),
};
