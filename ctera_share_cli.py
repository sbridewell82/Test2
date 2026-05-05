"""
CLI entry point for creating a CTERA share.

Called by the Ansible playbook so that Semaphore task-template variables
are passed straight through as command-line arguments.

Usage::

    python ctera_share_cli.py \\
        --host 192.168.1.100 \\
        --username admin \\
        --password secret \\
        --share-name Finance \\
        --directory /main/finance \\
        --comment "Finance share" \\
        --protocols smb nfs \\
        --acl '[{"principal_type":"DG","name":"CORP\\\\Finance","access":"RW"}]'
"""

import argparse
import json
import sys

from ctera_shares import ShareManager


def parse_args():
    p = argparse.ArgumentParser(description="Create a share on a CTERA Edge device")

    # Connection
    p.add_argument("--host",     required=True, help="CTERA Edge hostname or IP")
    p.add_argument("--username", required=True, help="Admin username")
    p.add_argument("--password", required=True, help="Admin password")

    # Share identity
    p.add_argument("--share-name",  required=True, help="Share name")
    p.add_argument("--directory",   required=True, help="Absolute path on the device")
    p.add_argument("--comment",     default="",    help="Optional description")

    # Protocols — pass one or more of: smb nfs afp ftp rsync pc_agent
    p.add_argument(
        "--protocols",
        nargs="*",
        default=["smb"],
        choices=["smb", "nfs", "afp", "ftp", "rsync", "pc_agent"],
        help="Protocols to enable (default: smb)",
    )

    # Permissions
    p.add_argument("--dir-permissions", type=int, default=777,
                   help="Unix directory permissions (default: 777)")
    p.add_argument("--access", default="winAclMode",
                   choices=["winAclMode", "publicMode"],
                   help="Windows ACL mode (default: winAclMode)")
    p.add_argument("--csc", default="manual",
                   choices=["manual", "documents", "programs", "disabled"],
                   help="Client-side caching mode (default: manual)")

    # ACL — JSON array of {principal_type, name, access}
    p.add_argument(
        "--acl",
        default="[]",
        help=(
            'JSON array of ACL entries. Example: '
            '[{"principal_type":"DG","name":"CORP\\\\Finance","access":"RW"}]'
        ),
    )

    # Misc
    p.add_argument("--indexed", action="store_true", help="Enable content indexing")
    p.add_argument("--delete",  action="store_true", help="Delete the share instead of creating it")

    return p.parse_args()


def main():
    args = parse_args()

    try:
        acl_raw = json.loads(args.acl)
    except json.JSONDecodeError as exc:
        print(f"ERROR: --acl is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(1)

    protocols = set(args.protocols or [])

    with ShareManager(args.host, args.username, args.password) as mgr:
        if args.delete:
            mgr.delete_share(args.share_name)
            print(f"Deleted share '{args.share_name}'")
            return

        acl = mgr.build_acl(acl_raw) if acl_raw else []

        mgr.create_share(
            name=args.share_name,
            directory=args.directory,
            acl=acl,
            access=args.access,
            csc=args.csc,
            dir_permissions=args.dir_permissions,
            comment=args.comment or None,
            export_to_afp="afp"      in protocols,
            export_to_ftp="ftp"      in protocols,
            export_to_nfs="nfs"      in protocols,
            export_to_pc_agent="pc_agent" in protocols,
            export_to_rsync="rsync"  in protocols,
            indexed=args.indexed,
        )
        print(f"Created share '{args.share_name}' on {args.host}")


if __name__ == "__main__":
    main()
