"""Demo data for development: ``python -m friends_api.cli seed-demo`` (contract section 1.12).

- ``context``: the shared ``DemoContext`` (users, group, categories by name, activities, a
  seeded ``random.Random`` and one fixed ``now`` per run).
- ``base``: the fixed setup every step builds on (3 demo users, one group with the default
  categories).
- one module per feature with its step functions (``categories``, ``activities``, ...).
- ``runner``: ``STEPS``, the ordered list of steps, and ``seed_demo``.

A feature adds demo data by adding a module with a ``step(db, ctx)`` function and one line to
``runner.STEPS``.
"""
