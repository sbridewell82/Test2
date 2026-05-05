"""
CLI entry point for creating an SMB share or NFS export on a Dell PowerScale cluster.

Called by the Ansible playbook so that Semaphore task-template variables
are passed straight through as command-line arguments.

Usage — SMB share::

    python onefs_share_cli.py \\
        --host 192.168.1.100 \\
        --username admin \\
        --password secret \\
        --share-name Finance \\
        --path /ifs/finance \\
        --description "Finance share" \\
        --type smb \\
        --permissions '[{"name":"CORP\\\\Finance","type":"group","permission":"full"}]'

Usage — NFS export::

    python onefs_share_cli.py \\
        --host 192.168.1.100 \\
        --username admin \\
        --password secret \\
        --path /ifs/data \\
        --description "Data export" \\
        --type nfs \\
        --rw-clients 10.0.0.0/24 \\
        --root-clients 10.0.0.5

Usage — delete SMB share::

    python onefs_share_cli.py --host ... --username ... --password ... \\
        --share-name Finance --type smb --delete

Usage — delete NFS export::

    python onefs_share_cli.py --host ... --username ... --password ... \\
        --type nfs --export-id 42 --delete
"""

import argparse
import json
import sys

from onefs_shares import ShareManager


def parse_args():
    p = argparse.ArgumentParser(
        description="Create or delete an SMB share / NFS export on a Dell PowerScale cluster"
    )

    # Connection
    p.add_argument("--host",       required=True, help="Cluster hostname or SmartConnect name")
    p.add_argument("--username",   required=True, help="Admin username")
    p.add_argument("--password",   required=True, help="Admin password")
    p.add_argument("--port",       type=int, default=8080, help="PAPI port (default 8080)")
    p.add_argument("--verify-ssl", action="store_true", help="Verify TLS certificate")

    # Zone
    p.add_argument("--zone", default="System", help="Access zone (default: System)")

    # Share type
    p.add_argument(
        "--type",
        choices=["smb", "nfs", "both"],
        default="smb",
        help="What to create: smb share, nfs export, or both (default: smb)",
    )

    # Identity
    p.add_argument("--share-name",   default="",  help="SMB share name (required for smb/both)")
    p.add_argument("--path",         required=True, help="Path on the cluster (e.g. /ifs/data)")
    p.add_argument("--description",  default="", help="Optional description")

    # SMB-specific
    p.add_argument("--browsable",    action="store_true", default=True,
                   help="Show share in browse lists (default: true)")
    p.add_argument(
        "--permissions",
        default="[]",
        help=(
            'JSON array of permission entries. Example: '
            '[{"name":"CORP\\\\Finance","type":"group","permission":"full","permission_type":"allow"}]'
        ),
    )

    # NFS-specific
    p.add_argument("--nfs-clients",  nargs="*", default=None,
                   help="Hosts/networks allowed to mount (default: all)")
    p.add_argument("--rw-clients",   nargs="*", default=None,
                   help="Hosts/networks with read-write access")
    p.add_argument("--ro-clients",   nargs="*", default=None,
                   help="Hosts/networks with read-only access")
    p.add_argument("--root-clients", nargs="*", default=None,
                   help="Hosts/networks exempt from root squash")
    p.add_argument("--all-dirs",     action="store_true",
                   help="Allow mounting any sub-directory")
    p.add_argument("--no-root-squash", action="store_true",
                   help="Disable root squash (map root to root)")

    # Delete mode
    p.add_argument("--delete",    action="store_true", help="Delete instead of create")
    p.add_argument("--export-id", type=int, default=None,
                   help="NFS export ID to delete (required when --delete --type nfs/both)")

    return p.parse_args()


def main():
    args = parse_args()

    try:
        perms_raw = json.loads(args.permissions)
    except json.JSONDecodeError as exc:
        print(f"ERROR: --permissions is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(1)

    with ShareManager(
        args.host, args.username, args.password,
        port=args.port, verify_ssl=args.verify_ssl,
    ) as mgr:

        do_smb = args.type in ("smb", "both")
        do_nfs = args.type in ("nfs", "both")

        if args.delete:
            if do_smb:
                if not args.share_name:
                    print("ERROR: --share-name is required to delete an SMB share", file=sys.stderr)
                    sys.exit(1)
                mgr.delete_smb_share(args.share_name, zone=args.zone)
                print(f"Deleted SMB share '{args.share_name}'")

            if do_nfs:
                if args.export_id is None:
                    print("ERROR: --export-id is required to delete an NFS export", file=sys.stderr)
                    sys.exit(1)
                mgr.delete_nfs_export(args.export_id, zone=args.zone)
                print(f"Deleted NFS export ID {args.export_id}")

            return

        if do_smb:
            if not args.share_name:
                print("ERROR: --share-name is required for SMB share creation", file=sys.stderr)
                sys.exit(1)

            permissions = mgr.build_permissions(perms_raw) if perms_raw else []

            mgr.create_smb_share(
                name=args.share_name,
                path=args.path,
                permissions=permissions,
                description=args.description,
                zone=args.zone,
                browsable=args.browsable,
            )
            print(f"Created SMB share '{args.share_name}' -> {args.path} on {args.host}")

        if do_nfs:
            result = mgr.create_nfs_export(
                paths=[args.path],
                description=args.description,
                zone=args.zone,
                clients=args.nfs_clients,
                read_write_clients=args.rw_clients,
                read_only_clients=args.ro_clients,
                root_clients=args.root_clients,
                all_dirs=args.all_dirs,
                no_root_squash=args.no_root_squash,
            )
            print(f"Created NFS export ID {result.id} -> {args.path} on {args.host}")


if __name__ == "__main__":
    main()
