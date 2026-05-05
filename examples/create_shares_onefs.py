"""
Examples: creating SMB shares and NFS exports on a Dell PowerScale cluster via ShareManager.
"""

from onefs_shares import ShareManager


def example_basic_smb_share():
    """Create a simple SMB share with no explicit permissions (inherits zone defaults)."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        mgr.create_smb_share(
            name="PublicData",
            path="/ifs/public",
            description="Open share for all users",
        )
        print("Created PublicData SMB share")


def example_smb_share_with_permissions():
    """Create an SMB share with domain group and user permission entries."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        permissions = mgr.build_permissions([
            {"name": "CORP\\Finance",  "type": "group", "permission": "full"},
            {"name": "CORP\\Auditors", "type": "group", "permission": "read"},
            {"name": "alice",          "type": "user",  "permission": "full"},
        ])

        mgr.create_smb_share(
            name="Finance",
            path="/ifs/finance",
            permissions=permissions,
            description="Finance department share",
        )
        print("Created Finance SMB share")


def example_smb_share_deny_entry():
    """Create an SMB share that explicitly denies access to a group."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        permissions = mgr.build_permissions([
            {"name": "Everyone",        "type": "wellknown", "permission": "read",   "permission_type": "allow"},
            {"name": "CORP\\TempUsers", "type": "group",    "permission": "full",   "permission_type": "deny"},
        ])

        mgr.create_smb_share(
            name="ReadOnlyArchive",
            path="/ifs/archive",
            permissions=permissions,
            description="Archive — read-only except explicitly denied",
        )
        print("Created ReadOnlyArchive SMB share")


def example_nfs_export_open():
    """Create an NFS export accessible by all hosts."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        result = mgr.create_nfs_export(
            paths=["/ifs/data"],
            description="General-purpose NFS data export",
        )
        print(f"Created NFS export ID {result.id} -> /ifs/data")


def example_nfs_export_restricted():
    """Create an NFS export restricted to a specific subnet, with a root-trusted host."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        result = mgr.create_nfs_export(
            paths=["/ifs/backup"],
            description="Backup NFS export",
            read_write_clients=["10.0.0.0/24"],
            root_clients=["10.0.0.5"],
        )
        print(f"Created restricted NFS export ID {result.id} -> /ifs/backup")


def example_smb_and_nfs_same_path():
    """Expose the same path via both SMB and NFS."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        permissions = mgr.build_permissions([
            {"name": "Everyone", "type": "wellknown", "permission": "full"},
        ])

        mgr.create_smb_share(
            name="MediaLibrary",
            path="/ifs/media",
            permissions=permissions,
            description="Media library (SMB)",
        )
        print("Created MediaLibrary SMB share")

        result = mgr.create_nfs_export(
            paths=["/ifs/media"],
            description="Media library (NFS)",
            read_write_clients=["10.0.0.0/24"],
        )
        print(f"Created MediaLibrary NFS export ID {result.id}")


def example_non_default_zone():
    """Create a share inside a non-default access zone."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        mgr.create_smb_share(
            name="HRData",
            path="/ifs/hr",
            description="HR zone share",
            zone="HR",
        )
        print("Created HRData share in HR access zone")


def example_list_and_delete():
    """List all SMB shares and NFS exports, then delete specific ones."""
    with ShareManager("192.168.1.100", "admin", "password") as mgr:
        smb_shares = mgr.list_smb_shares()
        print("SMB shares:")
        for share in smb_shares:
            print(f"  {share.name}  ->  {share.path}")

        nfs_exports = mgr.list_nfs_exports()
        print("NFS exports:")
        for export in nfs_exports:
            print(f"  ID {export.id}  ->  {export.paths}")

        mgr.delete_smb_share("OldShare")
        print("Deleted OldShare SMB share")

        mgr.delete_nfs_export(export_id=7)
        print("Deleted NFS export ID 7")


if __name__ == "__main__":
    example_basic_smb_share()
    example_smb_share_with_permissions()
    example_smb_share_deny_entry()
    example_nfs_export_open()
    example_nfs_export_restricted()
    example_smb_and_nfs_same_path()
    example_non_default_zone()
    example_list_and_delete()
