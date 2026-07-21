# Postfilter modules

Each module has one primary responsibility.  `NG.pm` orchestrates; `Context.pm` owns per-article state; `Checks/` contains policy checks; `Database.pm` owns SQLite; `HeaderTransform.pm` performs explicit header policy; `Report.pm` emits static HTML.
