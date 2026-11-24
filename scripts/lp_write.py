#!/usr/bin/python3 -I
"""Make Launchpad changes for the G Unity⁷ scripts (authenticated, with
launchpadlib): copy a version from the staging PPA to the main PPA (and wait
for copies) and retry failed builds.

Create the credentials file once with scripts/lp_login.py.
"""

import argparse
import os
import sys
import time

from launchpadlib import uris
from launchpadlib.credentials import Credentials
from launchpadlib.launchpad import Launchpad

## How long to wait for a copied version to appear in the main PPA (Pending or
##  Published). Publishing is up to Launchpad, and the first publication in a
##  new PPA takes hours.
COPY_TIMEOUT = 20 * 60


def login(args):
    """Log in with the credentials file only, never ask for an authorization."""
    if not os.path.isfile(args.credentials or ""):
        sys.exit(f"lp_write.py: credentials file {args.credentials} not found")
    credentials = Credentials.load_from_path(args.credentials)
    return Launchpad(credentials, None, None, service_root=uris.lookup_service_root("production"),
                     version="devel")


def archive(lp, ppa):
    owner, name = ppa.split("/")
    return lp.archives.getByReference(reference=f"~{owner}/ubuntu/{name}")


def source_of(arch, lp, source, version, series):
    entries = arch.getPublishedSources(source_name=source, version=version, exact_match=True,
                                       distro_series=lp.distributions["ubuntu"].getSeries(name_or_version=series))
    entries = [e for e in entries if e.status in ("Pending", "Published")]
    return entries[0] if entries else None


def cmd_copy(args):
    lp = login(args)
    staging = archive(lp, args.from_ppa)
    main = archive(lp, args.to_ppa)
    if not source_of(staging, lp, args.source, args.version, args.series):
        sys.exit(f"lp_write.py: {args.source} {args.version} is not in {args.from_ppa}")
    main.copyPackage(source_name=args.source, version=args.version, from_archive=staging,
                     to_series=args.series, to_pocket="Release", include_binaries=True)
    print(f"Copying {args.source} {args.version} to {args.to_ppa}", file=sys.stderr)
    if args.no_wait:
        return
    wait_for(lp, main, [(args.source, args.version)], args.to_ppa, args.series)


def wait_for(lp, arch, versions, ppa, series):
    """Wait until each (source, version) is in the PPA (Pending or Published),
    print "<source> <status>" for each, and fail with those that did not
    appear in COPY_TIMEOUT."""
    missing = list(versions)
    deadline = time.time() + COPY_TIMEOUT
    while missing and time.time() < deadline:
        for source, version in list(missing):
            copied = source_of(arch, lp, source, version, series)
            if copied:
                print(source, copied.status, flush=True)
                missing.remove((source, version))
        if missing:
            time.sleep(30)
    if missing:
        sys.exit(f"lp_write.py: not in {ppa} in time: {' '.join(f'{s} {v}' for s, v in missing)}")


def cmd_wait(args):
    lp = login(args)
    versions = [tuple(item.split("=", 1)) for item in args.versions]
    wait_for(lp, archive(lp, args.ppa), versions, args.ppa, args.series)


def cmd_retry(args):
    lp = login(args)
    ppa = archive(lp, args.ppa)
    source = source_of(ppa, lp, args.source, args.version, args.series)
    if not source:
        sys.exit(f"lp_write.py: {args.source} {args.version} is not in {args.ppa}")
    retried = 0
    for build in source.getBuilds():
        if build.can_be_retried:
            build.retry()
            retried += 1
            print(f"Retried {build.title}", file=sys.stderr)
    if not retried:
        sys.exit(f"lp_write.py: no build of {args.source} {args.version} can be retried")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--credentials", required=True, help="launchpadlib credentials file")
    sub = parser.add_subparsers(required=True)

    p = sub.add_parser("copy", help="copy a version with its binaries between PPAs")
    p.add_argument("source")
    p.add_argument("version")
    p.add_argument("--from", dest="from_ppa", required=True)
    p.add_argument("--to", dest="to_ppa", required=True)
    p.add_argument("--series", required=True)
    p.add_argument("--no-wait", action="store_true", help="only ask for the copy (see wait)")
    p.set_defaults(func=cmd_copy)

    p = sub.add_parser("wait", help="wait until copied versions are in a PPA")
    p.add_argument("versions", nargs="+", metavar="source=version")
    p.add_argument("--ppa", required=True)
    p.add_argument("--series", required=True)
    p.set_defaults(func=cmd_wait)

    p = sub.add_parser("retry", help="retry the failed builds of a version")
    p.add_argument("source")
    p.add_argument("version")
    p.add_argument("--ppa", required=True)
    p.add_argument("--series", required=True)
    p.set_defaults(func=cmd_retry)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
