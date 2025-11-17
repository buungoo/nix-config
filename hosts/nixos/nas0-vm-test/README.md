This is a **minimal VM configuration** to test the nas0 btrfs + disko storage layout **without** all the nas0-specific services (containers, networking, etc.).

1. Build `nix build .#nixosConfigurations.nas0-vm-test.config.system.build.vm`
2. Run `./result/bin/run-nas0-vm-test-vm`
3. Validate
    ```bash
    # Check all mounts
    check-mounts

    # Show btrfs filesystems
    btrfs-show

    # List all btrfs subvolumes
    sudo btrfs subvolume list /

    # Check NOCOW on parity/content
    lsattr /mnt/disks/parity0
    lsattr /mnt/snapraid-content/data0

    # Verify snapraid config
    sr-status

    # Check mergerfs union
    ls -la /mnt/storage
    touch /mnt/storage/test.txt
    ls -la /mnt/disks/data0/  # Should see test.txt

    # List snapper configs
    snap-list

    # Show partition layout
    lsblk

    # Show filesystem usage
    df -h

    # Inspect btrfs
    sudo btrfs filesystem show
    sudo btrfs filesystem usage /
    ```
4. Success

    1. **All mounts present:**
        - `/` (root)
        - `/boot` (ESP)
        - `/nix` (nix store)
        - `/persist` (state)
        - `/swap` (swapfile)
        - `/mnt/root/data*` (root access)
        - `/mnt/disks/data*` (main storage)
        - `/mnt/disks/data0/.snapshots` (snapshots)
        - `/mnt/snapraid-content/data*` (content)
        - `/mnt/disks/parity*` (parity)
        - `/mnt/storage` (mergerfs pool)

    2. **NOCOW set correctly:**
        ```bash
        lsattr /mnt/disks/parity0
        # Should show: ---------------C---- /mnt/disks/parity*

        lsattr /mnt/snapraid-content/data*
        # Should show: ---------------C---- /mnt/snapraid-content/data*
        ```

    3. **Snapraid recognizes config:**
        ```bash
        sr-status
        # Should show data and parity disks
        ```

    4. **Mergerfs works:**
        ```bash
        touch /mnt/storage/test.txt
        ls /mnt/disks/data0/test.txt    # File should exist
        ```
