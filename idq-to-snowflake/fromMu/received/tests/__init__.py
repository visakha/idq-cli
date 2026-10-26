# This file exists on purpose: it makes `tests` a package, so
# pytest's prepend import mode inserts the project root (not just
# tests/) into sys.path.  Without it, `import app` fails when
# pytest is run as a bare `pytest` command (as opposed to
# `python -m pytest`, which puts the current directory on the
# path and masked the problem).  See pyproject.toml's pythonpath
# setting, which is the belt-and-braces companion to this file.
