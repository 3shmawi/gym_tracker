# Use cases

Put one class per business action here, e.g. `ResolveStartupLocale`.
A use case depends only on domain interfaces (repositories) and entities.

Settings has no business rules — it only reads and writes preferences — so
its presentation layer talks to `SettingsRepository` directly. Add a use case
as soon as a feature has logic beyond "load / save" (validation, combining
repositories, calculations). Every use case gets a unit test in
`test/features/<feature>/domain/usecases/`.
