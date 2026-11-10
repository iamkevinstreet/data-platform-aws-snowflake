########################################################################
#                                                                      #
#                           tests/support.py                           #
#                                                                      #
########################################################################
"""
Author:            Kevin Street
Created on:        2026-11-10
Last modified on:  2026-11-10

What the tests share: the repository's root, where infra/ is.
"""

########################################################################
#                                                                      #
#                               Imports                                #
#                                                                      #
########################################################################
# Standard library
from __future__ import annotations

from pathlib import Path
from typing import Final

# Third-party
from kds.logs import get_logger

########################################################################
#                                                                      #
#                           Global constants                           #
#                                                                      #
########################################################################
log = get_logger(__name__)

########################################################################
#                                                                      #
#                           Local constants                            #
#                                                                      #
########################################################################
# log.debug("Sets the repository's root, where infra/ is")
REPO: Final = Path(__file__).resolve().parents[1]
