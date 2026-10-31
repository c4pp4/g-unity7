#!/usr/bin/python3 -I
"""Make the Launchpad credentials file of lp_write.py (secret LP_CREDENTIALS):
an OAuth token of the consumer g-unity7 with "Change Non-Private Data" only.

Usage: lp_login.py <credentials file>

Open the printed page, choose "Change Non-Private Data", then press Enter.
"""

import os
import sys

from launchpadlib.credentials import AuthorizeRequestTokenWithURL
from launchpadlib.launchpad import Launchpad


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip())
    path = sys.argv[1]
    if os.path.exists(path):
        sys.exit(f"lp_login.py: {path} exists, remove it first")
    engine = AuthorizeRequestTokenWithURL("production", consumer_name="g-unity7",
                                          allow_access_levels=["WRITE_PUBLIC"])
    lp = Launchpad.login_with(service_root="production", version="devel",
                              authorization_engine=engine, credentials_file=path)
    print(f"Logged in as {lp.me.name}, credentials saved to {path}")


if __name__ == "__main__":
    main()
