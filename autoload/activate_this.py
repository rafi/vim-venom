# -*- coding: utf-8 -*-
"""Activate virtualenv for current interpreter:
Source: https://github.com/pypa/virtualenv

Use exec(open(this_file).read(), {'__file__': this_file}).
"""
import os
import site
import sys

try:
    abs_file = os.path.abspath(__file__)
except NameError:
    raise AssertionError(
        "You must use exec(open(this_file).read(), {'__file__': this_file}))")

# Prepend bin to PATH (this file is inside the bin directory)
bin_dir = os.path.dirname(abs_file)
os.environ["PATH"] = os.pathsep.join(
    [bin_dir] + os.environ.get("PATH", "").split(os.pathsep))

# Virtual env is right above bin directory
base = os.path.dirname(bin_dir)
os.environ["VIRTUAL_ENV"] = base

# Concat site-packages library path
IS_WIN = sys.platform == "win32"
IS_PYPY = hasattr(sys, "pypy_version_info")
IS_JYTHON = sys.platform.startswith("java")
if IS_JYTHON or IS_WIN:
    site_packages = os.path.join(base, "Lib", "site-packages")
elif IS_PYPY:
    site_packages = os.path.join(base, "site-packages")
else:
    python_lib = "python{}.{}".format(*sys.version_info)
    site_packages = os.path.join(base, "lib", python_lib, "site-packages")

# Add the virtual environment libraries to the host python import mechanism
prev_length = len(sys.path)
site.addsitedir(site_packages)
sys.path[:] = sys.path[prev_length:] + sys.path[0:prev_length]

sys.real_prefix = sys.prefix
sys.prefix = base

#  vim: set ts=4 sw=4 tw=80 et :
