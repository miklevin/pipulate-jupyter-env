"""
Pipulate: A hand-cranked, local-first context compiler — the successor to AI SEO software.

Your data. Your AI. Your machine. Your control.

This package provides the `pipulate` command for discovering and installing
the full Pipulate environment via PyPI, while the actual application runs
in a Nix-managed environment for complete reproducibility.

Usage:
    pip install pipulate
    pipulate
"""

__version__ = "2.56"
# APOSTROPHES RESTORED (2026-08-04). They were stripped as a workaround for
# flake.nix's descMatch regex, whose character class excluded ' from the
# CAPTURE and truncated the banner to "(So)". That regex was fixed in the same
# ride, and this line is now the only thing that exercises the fix: with the
# apostrophes gone, the old regex and the new one print an IDENTICAL string, so
# the straddle could not discriminate between a landed patch and a missing one.
# A convention the author has to remember ("no apostrophes in version names")
# is not a property of the system; the regex is. Blast radius is one banner:
# nothing but flake.nix reads this name -- version_sync.py syncs __version__
# and __description__, never this. So'wI' chu' -- "engage the cloaking device."
__version_description__ = "NPvg.org Installer Exits"
# SPDX expression, single source of truth, synced into pyproject.toml by
# scripts/release/version_sync.py. "-or-later" (not bare AGPL-3.0, which is
# deprecated SPDX) because the header below grants "any later version".
__license__ = "AGPL-3.0-or-later"
__email__ = "pipulate@gmail.com"
__description__ = "The context compiler that helps you prompt well — local-first, Nix-reproducible, replayable. The successor to AI SEO software."

# Pipulate: A hand-cranked, local-first context compiler — the successor to AI SEO software.
# Copyright (C) 2026 Michael Jay Levin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# SINGLE SOURCE OF TRUTH FOR VERSION AND DESCRIPTION
# This version number and description are used across all components:
# - pyproject.toml (synced via version_sync.py)
# - flake.nix (reads this file directly at build time)
# - install.sh (synced via version_sync.py)
# - server.py startup banners (reads this file directly)
# Update these values and (under `nix develop .#quiet` env) run: release
