# Kindle Pilot macOS User Guide

Kindle Pilot is a macOS Kindle helper tool. It can control page turning, send books, sync clippings, and sync the native vocabulary builder on a jailbroken Kindle through SSH. It also supports importing `My Clippings.txt` and `vocab.db` locally, so a non-jailbroken Kindle can also be used to organize notes and vocabulary.

## Open Source License

This project is open source under GNU General Public License v3.0 only (GPL-3.0-only). You are free to use, modify, and distribute the code. If you distribute a modified version or a derivative work based on this project, you also need to make the corresponding source code available according to the requirements of GPLv3. The software is provided as is, without any warranty.

## Installation

Using the DMG installer is recommended:

1. Open `Kindle_Pilot-0.0.4.dmg`.
2. Drag `Kindle Pilot.app` to `Applications`.
3. Open `Kindle Pilot` from Applications or Spotlight.

If macOS says it cannot verify the developer, allow it in System Settings -> Privacy & Security, or right-click the app and choose Open.

## Connect Kindle

A jailbroken Kindle can use the full feature set. First confirm that SSH is available on the Kindle, then fill in the following in the app settings:

- IP: the LAN IP of the Kindle, for example `192.168.31.204`
- Username: usually `root`
- Password: your Kindle SSH password, default is kindle

After filling them in, click Save, then click Test Connection.

## Remote Page Turning

Remote page turning requires a jailbroken Kindle, and touch events must be writable through SSH.

Recommended flow:

1. Click Test Connection on the Remote page.
2. Click Detect, so the app can find the touch device.
3. Click Check Commands.
4. If it reports missing page-turn commands, record Previous Page and Next Page separately for portrait and landscape orientation.
5. After recording, you can use the Previous Page and Next Page buttons, or enable keyboard page turning.

When recording, follow the prompt and perform the corresponding page-turn gesture on the Kindle.

## Send Books

The send-books feature requires a jailbroken Kindle with SSH access.

1. Open the Send Books page.
2. Select `.azw3`, `.mobi`, `.epub`, or `.pdf` files.
3. The app checks whether books with the same names already exist under `/mnt/us/documents` on the Kindle.
4. Confirm and upload.

## Sync Clippings

A jailbroken Kindle can sync directly:

1. Open the Clippings page.
2. Click Get -> Sync from Kindle.
3. The app downloads `/mnt/us/documents/My Clippings.txt` from the Kindle and parses it.

After parsing, you can browse highlights, notes, and bookmarks by book, and export them as Markdown, CSV, or TXT.

## Import Local Clippings

For a non-jailbroken Kindle, you can first copy the file to the Mac, then import it:

1. Connect the Kindle with USB.
2. Copy `My Clippings.txt` from the Kindle's `documents` directory to the Mac.
3. Open the Clippings page in the app.
4. Click Get -> Import My Clippings.txt.
5. Select the `My Clippings.txt` you just copied.

After import, the app copies the file to its own cache directory and then parses it. Later, you can click Reparse Cache to read it again.

## Sync Vocabulary

A jailbroken Kindle can directly sync the native vocabulary builder:

1. Open the Vocabulary page.
2. Click Get -> Sync Vocabulary from Kindle.
3. The app downloads `/mnt/us/system/vocabulary/vocab.db` from the Kindle and parses it.

The vocabulary builder filters Chinese entries and combines word candidates from clippings to mark focus words.

## Import Local Vocabulary

For a non-jailbroken Kindle, you can first copy the file to the Mac, then import it:

1. Connect the Kindle with USB.
2. Try to find and copy `system/vocabulary/vocab.db` to the Mac.
3. Open the Vocabulary page in the app.
4. Click Get -> Import vocab.db.
5. Select the `vocab.db` you just copied.

Note: Different Kindle models and system versions expose different USB file ranges. Older Kindles are usually more likely to show `system/vocabulary/vocab.db` directly. Newer MTP devices may require Amazon USB File Manager, OpenMTP, or similar tools, and may not expose this file at all.

## FAQ

### What features can a non-jailbroken Kindle use?

Available:

- Import `My Clippings.txt` locally
- Import `vocab.db` locally, provided that it can be copied from the Kindle
- Browse and export clippings
- Browse and export vocabulary

Unavailable:

- SSH remote page turning
- Touch event recording
- SSH book transfer
- Sync files directly from Kindle

These features all require SSH and system file access after jailbreaking.
