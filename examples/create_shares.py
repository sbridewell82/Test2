"""
Examples: creating shares on a CTERA Edge device via ShareManager.
"""

from ctera_shares import ShareManager


def example_basic_smb_share():
    """Create a simple SMB share with no ACL restrictions."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        mgr.create_share(
            name="PublicData",
            directory="/main/public",
            comment="Open share for all users",
        )
        print("Created PublicData share")


def example_share_with_acl():
    """Create a share with domain group/user ACL entries."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        acl = mgr.build_acl([
            {"principal_type": "DG", "name": "CORP\\Finance",   "access": "RW"},
            {"principal_type": "DG", "name": "CORP\\Auditors",  "access": "RO"},
            {"principal_type": "DU", "name": "alice@corp.com",  "access": "RW"},
        ])

        mgr.create_share(
            name="Finance",
            directory="/main/finance",
            acl=acl,
            comment="Finance department share",
        )
        print("Created Finance share")


def example_multi_protocol_share():
    """Create a share accessible via SMB, NFS, FTP, and RSYNC."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        acl = mgr.build_acl([
            {"principal_type": "LG", "name": "Everyone", "access": "RW"},
        ])

        mgr.create_share(
            name="MediaLibrary",
            directory="/main/media",
            acl=acl,
            comment="Media library - multi-protocol",
            export_to_nfs=True,
            export_to_ftp=True,
            export_to_rsync=True,
            export_to_afp=True,
        )
        print("Created MediaLibrary share")


def example_backup_agent_share():
    """Create a share used as a CTERA Backup Agent destination."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        acl = mgr.build_acl([
            {"principal_type": "DG", "name": "CORP\\Workstations", "access": "RW"},
        ])

        mgr.create_share(
            name="Backups",
            directory="/main/backups",
            acl=acl,
            comment="CTERA Agent backup destination",
            export_to_pc_agent=True,
        )
        print("Created Backups share")


def example_list_and_delete():
    """List all shares and delete one by name."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        shares = mgr.list_shares()
        print("Current shares:")
        for share in shares:
            print(f"  {share.name}")

        mgr.delete_share("OldShare")
        print("Deleted OldShare")


if __name__ == "__main__":
    example_basic_smb_share()
    example_share_with_acl()
    example_multi_protocol_share()
    example_backup_agent_share()
    example_list_and_delete()
