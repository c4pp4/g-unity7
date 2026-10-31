#!/usr/bin/python3 -I
"""Launchpad changes of the G Unity⁷ scripts (authenticated, launchpadlib):
copy a version from the staging PPA to the main PPA, retry failed builds.

The credentials file is made once with:
  python3 -c 'from launchpadlib.launchpad import Launchpad;
    Launchpad.login_with("g-unity7", "production", credentials_file="lp-credentials")'
"""

import argparse
import sys
import time

from launchpadlib.launchpad import Launchpad

## How long to wait for a copied version to be published in the main PPA.
PUBLISH_TIMEOUT = 45 * 60


def login(args):
    return Launchpad.login_with("g-unity7", "production", version="devel",
                                credentials_file=args.credentials)


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
    deadline = time.time() + PUBLISH_TIMEOUT
    while time.time() < deadline:
        published = source_of(main, lp, args.source, args.version, args.series)
        if published and published.status == "Published":
            print(f"Published {args.source} {args.version} in {args.to_ppa}", file=sys.stderr)
            return
        time.sleep(60)
    sys.exit(f"lp_write.py: {args.source} {args.version} not published in {args.to_ppa} in time")


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
    p.set_defaults(func=cmd_copy)

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
