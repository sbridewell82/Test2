"""
CTERA API - Share Management

Provides a ShareManager class for creating and managing shares on CTERA Edge devices.
"""

from cterasdk import Edge
from cterasdk import edge_enum, edge_types


class ShareManager:
    """Manages shares on a CTERA Edge device."""

    def __init__(self, host, username, password):
        """
        Connect and authenticate to a CTERA Edge device.

        :param host: Hostname or IP address of the CTERA Edge device
        :param username: Admin username
        :param password: Admin password
        """
        self.edge = Edge(host)
        self.edge.login(username, password)

    def create_share(
        self,
        name,
        directory,
        acl=None,
        access="winAclMode",
        csc="manual",
        dir_permissions=777,
        comment=None,
        export_to_afp=False,
        export_to_ftp=False,
        export_to_nfs=False,
        export_to_pc_agent=False,
        export_to_rsync=False,
        indexed=False,
        trusted_nfs_clients=None,
    ):
        """
        Create a share on the CTERA Edge device.

        :param name: Share name (used as the network share name)
        :param directory: Absolute path to the directory to share
        :param acl: List of ShareAccessControlEntry objects; defaults to no ACL entries
        :param access: Windows ACL mode - 'winAclMode' (default) or 'publicMode'
        :param csc: Client-side caching mode - 'manual', 'documents', 'programs', or 'disabled'
        :param dir_permissions: Unix permissions for the directory (default 777)
        :param comment: Optional description shown to users browsing the share
        :param export_to_afp: Enable Apple Filing Protocol (AFP) access
        :param export_to_ftp: Enable FTP access
        :param export_to_nfs: Enable NFS access
        :param export_to_pc_agent: Allow CTERA Backup Agents to connect
        :param export_to_rsync: Enable RSYNC access
        :param indexed: Enable content indexing for search
        :param trusted_nfs_clients: List of NFSv3AccessControlEntry objects for NFS client restrictions
        :returns: The created share object
        """
        return self.edge.shares.add(
            name=name,
            directory=directory,
            acl=acl or [],
            access=access,
            csc=csc,
            dir_permissions=dir_permissions,
            comment=comment,
            export_to_afp=export_to_afp,
            export_to_ftp=export_to_ftp,
            export_to_nfs=export_to_nfs,
            export_to_pc_agent=export_to_pc_agent,
            export_to_rsync=export_to_rsync,
            indexed=indexed,
            trusted_nfs_clients=trusted_nfs_clients,
        )

    def build_acl(self, entries):
        """
        Build an ACL list from a list of dicts.

        Each dict must have:
          - 'principal_type': one of 'LU', 'LG', 'DU', 'DG'
          - 'name': principal name (e.g. 'alice', 'DOMAIN\\group')
          - 'access': one of 'RW', 'RO', 'NA'

        Example::

            acl = manager.build_acl([
                {'principal_type': 'DG', 'name': 'CORP\\Finance', 'access': 'RW'},
                {'principal_type': 'DU', 'name': 'bob@corp.com', 'access': 'RO'},
            ])

        :param entries: List of dicts describing ACL entries
        :returns: List of ShareAccessControlEntry objects
        """
        principal_type_map = {
            "LU": edge_enum.PrincipalType.LU,
            "LG": edge_enum.PrincipalType.LG,
            "DU": edge_enum.PrincipalType.DU,
            "DG": edge_enum.PrincipalType.DG,
        }
        access_mode_map = {
            "RW": edge_enum.FileAccessMode.RW,
            "RO": edge_enum.FileAccessMode.RO,
            "NA": edge_enum.FileAccessMode.NA,
        }

        acl = []
        for entry in entries:
            principal_type = principal_type_map[entry["principal_type"].upper()]
            access_mode = access_mode_map[entry["access"].upper()]
            acl.append(
                edge_types.ShareAccessControlEntry(
                    principal_type,
                    entry["name"],
                    access_mode,
                )
            )
        return acl

    def delete_share(self, name):
        """
        Delete a share by name.

        :param name: Name of the share to delete
        """
        self.edge.shares.delete(name)

    def list_shares(self):
        """
        Return a list of all shares on the device.

        :returns: List of share objects
        """
        return self.edge.shares.get()

    def logout(self):
        """Log out from the CTERA Edge device."""
        self.edge.logout()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.logout()
