"""
OneFS (Dell PowerScale) API - Share Management

Provides a ShareManager class for creating and managing SMB shares and NFS exports
on a Dell PowerScale (OneFS) cluster via the isilon_sdk REST client.
"""

import urllib3

import isilon_sdk.v9_5_0 as isi_sdk

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

_PERMISSION_MAP = {
    "full":   "full",
    "change": "change",
    "read":   "read",
}

_PERM_TYPE_MAP = {
    "allow": "allow",
    "deny":  "deny",
}

_TRUSTEE_TYPE_MAP = {
    "user":  "user",
    "group": "group",
    "wellknown": "wellknown",
}


class ShareManager:
    """Manages SMB shares and NFS exports on a Dell PowerScale (OneFS) cluster."""

    def __init__(self, host, username, password, port=8080, verify_ssl=False):
        """
        Connect and authenticate to a OneFS cluster.

        :param host: Hostname or IP address of the cluster (any node or SmartConnect name)
        :param username: Admin username
        :param password: Admin password
        :param port: PAPI port (default 8080)
        :param verify_ssl: Verify TLS certificate (default False for self-signed certs)
        """
        config = isi_sdk.Configuration()
        config.host = f"https://{host}:{port}"
        config.username = username
        config.password = password
        config.verify_ssl = verify_ssl

        self._api_client = isi_sdk.ApiClient(config)
        self._protocols = isi_sdk.ProtocolsApi(self._api_client)

    # ── SMB shares ────────────────────────────────────────────────────────

    def create_smb_share(
        self,
        name,
        path,
        permissions=None,
        description="",
        zone="System",
        browsable=True,
        file_create_mask=0o700,
        file_create_mode=0o100,
        directory_create_mask=0o700,
        directory_create_mode=0o110,
        allow_delete_readonly=False,
        allow_execute_always=False,
        inheritable_path_acl=False,
    ):
        """
        Create an SMB share on the cluster.

        :param name: Share name visible to Windows clients
        :param path: Absolute path on the cluster filesystem (must start with /ifs)
        :param permissions: List of SmbSharePermission objects; defaults to no ACL entries
        :param description: Optional description shown to browsing clients
        :param zone: Access zone (default 'System')
        :param browsable: Show the share in network browse lists (default True)
        :param file_create_mask: Octal mask applied when creating files (default 0o700)
        :param file_create_mode: Octal mode bits OR'd in for new files (default 0o100)
        :param directory_create_mask: Octal mask for new directories (default 0o700)
        :param directory_create_mode: Octal mode bits OR'd in for new directories (default 0o110)
        :param allow_delete_readonly: Allow deletion of read-only files (default False)
        :param allow_execute_always: Allow execute even without x bit (default False)
        :param inheritable_path_acl: Propagate ACL to new files/dirs (default False)
        :returns: The created share object
        """
        smb_share = isi_sdk.SmbShare(
            name=name,
            path=path,
            description=description,
            permissions=permissions or [],
            browsable=browsable,
            file_create_mask=file_create_mask,
            file_create_mode=file_create_mode,
            directory_create_mask=directory_create_mask,
            directory_create_mode=directory_create_mode,
            allow_delete_readonly=allow_delete_readonly,
            allow_execute_always=allow_execute_always,
            inheritable_path_acl=inheritable_path_acl,
        )
        return self._protocols.create_smb_share(smb_share=smb_share, zone=zone)

    def build_permissions(self, entries):
        """
        Build an SMB permission list from a list of dicts.

        Each dict must have:
          - 'name': trustee name (e.g. 'Everyone', 'CORP\\\\Finance', 'alice')
          - 'type': trustee type — 'user', 'group', or 'wellknown' (default 'group')
          - 'permission': 'full', 'change', or 'read' (default 'full')
          - 'permission_type': 'allow' or 'deny' (default 'allow')

        Example::

            perms = mgr.build_permissions([
                {'name': 'CORP\\\\Finance',  'type': 'group', 'permission': 'full'},
                {'name': 'CORP\\\\Auditors', 'type': 'group', 'permission': 'read'},
                {'name': 'alice',           'type': 'user',  'permission': 'full'},
            ])

        :param entries: List of dicts describing permission entries
        :returns: List of SmbSharePermission objects
        """
        permissions = []
        for entry in entries:
            trustee_type = _TRUSTEE_TYPE_MAP[entry.get("type", "group").lower()]
            permission = _PERMISSION_MAP[entry.get("permission", "full").lower()]
            permission_type = _PERM_TYPE_MAP[entry.get("permission_type", "allow").lower()]

            trustee = isi_sdk.SmbShareTrustee(
                name=entry["name"],
                type=trustee_type,
            )
            permissions.append(
                isi_sdk.SmbSharePermission(
                    permission=permission,
                    permission_type=permission_type,
                    trustee=trustee,
                )
            )
        return permissions

    def delete_smb_share(self, name, zone="System"):
        """
        Delete an SMB share by name.

        :param name: Name of the share to delete
        :param zone: Access zone (default 'System')
        """
        self._protocols.delete_smb_share(smb_share_id=name, zone=zone)

    def list_smb_shares(self, zone="System"):
        """
        Return all SMB shares in an access zone.

        :param zone: Access zone (default 'System')
        :returns: List of SMB share objects
        """
        return self._protocols.list_smb_shares(zone=zone).shares

    # ── NFS exports ───────────────────────────────────────────────────────

    def create_nfs_export(
        self,
        paths,
        description="",
        zone="System",
        clients=None,
        read_write_clients=None,
        read_only_clients=None,
        root_clients=None,
        all_dirs=False,
        no_root_squash=False,
    ):
        """
        Create an NFS export on the cluster.

        :param paths: List of absolute paths to export (e.g. ['/ifs/data'])
        :param description: Optional description
        :param zone: Access zone (default 'System')
        :param clients: Hosts/networks allowed to mount (None means all)
        :param read_write_clients: Hosts/networks granted read-write access
        :param read_only_clients: Hosts/networks granted read-only access
        :param root_clients: Hosts/networks exempt from root squash
        :param all_dirs: Allow clients to mount any sub-directory (default False)
        :param no_root_squash: Map root UID/GID to root instead of nobody (default False)
        :returns: The created export object
        """
        nfs_export = isi_sdk.NfsExport(
            paths=paths,
            description=description,
            clients=clients,
            read_write_clients=read_write_clients,
            read_only_clients=read_only_clients,
            root_clients=root_clients,
            all_dirs=all_dirs,
        )
        # no_root_squash is expressed via map_root in the SDK
        if no_root_squash:
            nfs_export.map_root = isi_sdk.NfsExportMapRoot(enabled=False)

        return self._protocols.create_nfs_export(nfs_export=nfs_export, zone=zone)

    def delete_nfs_export(self, export_id, zone="System"):
        """
        Delete an NFS export by ID.

        :param export_id: Numeric ID of the export to delete
        :param zone: Access zone (default 'System')
        """
        self._protocols.delete_nfs_export(nfs_export_id=export_id, zone=zone)

    def list_nfs_exports(self, zone="System"):
        """
        Return all NFS exports in an access zone.

        :param zone: Access zone (default 'System')
        :returns: List of NFS export objects
        """
        return self._protocols.list_nfs_exports(zone=zone).exports

    # ── Lifecycle ─────────────────────────────────────────────────────────

    def close(self):
        """Close the underlying API client connection pool."""
        self._api_client.rest_client.pool_manager.clear()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
