# Blue Google Drive backup format

The visible file is `Blue-<first-eight-installation-characters>.bluebackup` in a Blue-created `Blue` folder. Each installation updates one file; another device's file is never silently overwritten. This is a backup, not bidirectional synchronization. Google Drive may maintain its own revision history; Blue does not create a file for each edit.

## Container v2

Bytes start with UTF-8 `BLUEBACKUP`, NUL, byte `0x02`. The remaining bytes are JSON with `version: 1`, `keyID` (a non-secret Drive file ID), and base64 `ciphertext`. Ciphertext is the container from EncryptedBackup: UTF-8 `BLUEBACKUP`, NUL, byte `0x01`, then CryptoKit AES-GCM combined bytes (12-byte nonce, ciphertext, 16-byte authentication tag). The inner prefix is authenticated additional data. A fresh nonce is generated for each save.

The decrypted JSON is AppBackupSnapshot v1, containing library (LibraryState v3), preferences, and provider credentials. Dates use Swift Codable's seconds since 2001-01-01 UTC; Data is base64. Readers must reject unknown versions and invalid authentication tags. Google OAuth tokens, device permissions and storage bookmarks are not part of the snapshot; reconnect Google and re-establish system permissions on another device. Stored events and alarm adapters preserve scheduling intent but do not grant OS alarm permission on another device.

## Account-protected recovery

`keyID` refers to a 32-byte AES key file in Blue's Google Drive appDataFolder. The visible backup contains no key. Access requires the same Google account and authorization for this application's private data. Another Blue platform client must be registered in the same Google Cloud application/project and implement this format; an unrelated application cannot automatically read Blue's private key data. Actual future-platform authorization still requires integration testing.

This is account-protected file encryption, not end-to-end encryption against Google: Google hosts both the ciphertext and account-protected key. Deleting the private recovery data can make an existing copy unreadable. The uploader refuses to overwrite a file whose key is missing, invalid, or cannot authenticate the prior contents.

## Write and recovery behavior

Library commits, saved preference changes and provider-key changes enqueue the latest snapshot. Writes are coalesced and serialized. No data leaves the device until the user has granted both drive.file and drive.appdata. The uploader reserves IDs before creation, preserves them across uncertain outcomes, checks for ambiguous file matches and downloads the uploaded ciphertext to verify it before displaying success. A foreground activation retries and revalidates storage. Offline or background suspension can delay a cloud copy; the local store remains authoritative.

DriveBackupService.readSnapshot downloads and decrypts a file with its account recovery key. Full replacement of the running library, OS alarm re-registration and a restore UI are separate work; the reader never automatically replaces local data.
