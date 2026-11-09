//
//  SmartShelfSettingsSection.swift
//  TwoTabs Notch - Smart Shelf
//
//  "Smart Shelf" section of the Shelf settings pane.
//

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

struct SmartShelfSettingsSection: View {
    @Default(.smartShelfUploadHost) private var uploadHost
    @Default(.smartShelfLitterboxExpiry) private var expiry
    @Default(.smartShelfScreenshotsEnabled) private var screenshotsEnabled
    @Default(.smartShelfScreenshotFolderPath) private var screenshotFolderPath
    @Default(.smartShelfCatchCopiedImages) private var catchCopiedImages
    @Default(.smartShelfCaptureKeepCount) private var keepCount
    @Default(.smartShelfCapturePreview) private var capturePreview
    @Default(.smartShelfShrinkMaxDimension) private var maxDimension
    @Default(.smartShelfShrinkQuality) private var quality

    private func chooseFolder() {
        if ScreenshotWatcher.chooseFolder() {
            screenshotFolderPath = Defaults[.smartShelfScreenshotFolderPath]
        }
    }

    var body: some View {
        Section {
            Picker("Upload host", selection: $uploadHost) {
                ForEach(SmartShelfUploadHost.allCases) { host in
                    Text(host.title).tag(host)
                }
            }
            if uploadHost == .litterbox {
                Picker("Litterbox link expires after", selection: $expiry) {
                    ForEach(LitterboxExpiry.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            Text("Uploads create public links: anyone with the link can open the file. Limits: Litterbox 1 GB, Catbox 200 MB.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Catch screenshots & recordings", isOn: $screenshotsEnabled)
                .onChange(of: screenshotsEnabled) {
                    // Turning it on without a folder: ask for one right away (copied images work without one).
                    if screenshotsEnabled, Defaults[.smartShelfScreenshotFolderBookmark] == nil {
                        chooseFolder()
                    }
                }
            if screenshotsEnabled, screenshotFolderPath == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Let TwoTabs Notch catch your screenshots?")
                        .font(.callout.weight(.semibold))
                    Text("macOS only lets the app look inside a folder you choose. Pick the folder your screenshots and screen recordings are saved to (usually Desktop).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Choose your screenshot folder…") { chooseFolder() }
                }
            } else {
                HStack {
                    Text("Screenshot folder")
                    Spacer()
                    Text(screenshotFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "No folder chosen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("Change…") { chooseFolder() }
                }
                .disabled(!screenshotsEnabled)
            }
            Text("New screenshots (⌘⇧3, ⌘⇧4, ⌘⇧5) and screen recordings (.mov) in that folder are added to the shelf. Your Mac's screenshot folder is suggested in the picker.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Also catch copied images", isOn: $catchCopiedImages)
                .disabled(!screenshotsEnabled)
            Text("Screenshots copied with ⌃⌘⇧3 / ⌃⌘⇧4 and any other image you copy are added as temporary items. Turn this off if you copy many images.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(value: $keepCount, in: 1...50) {
                HStack {
                    Text("Keep last captures on the shelf")
                    Spacer()
                    Text("\(keepCount)").foregroundStyle(.secondary)
                }
            }
            .disabled(!screenshotsEnabled)
            Text("Older auto-added captures leave the shelf (the files themselves are never deleted). Items you add yourself stay.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Show preview in notch", isOn: $capturePreview)
                .disabled(!screenshotsEnabled)
            Text("A small thumbnail and label appear next to the notch for a few seconds. Opening the notch then jumps to the Shelf with the new capture selected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            KeyboardShortcuts.Recorder("Clear shelf", name: .clearShelf)

            Stepper(value: $maxDimension, in: 320...8192, step: 160) {
                HStack {
                    Text("Shrink: longest side")
                    Spacer()
                    Text("\(maxDimension) px").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Shrink: JPEG quality")
                Slider(value: $quality, in: 0.3...1.0, step: 0.05)
                Text("\(Int((quality * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        } header: {
            Text("Smart Shelf")
        } footer: {
            Text("Select shelf items to get the quick-action bar: shrink, convert, remove background, copy text (OCR), make or merge PDFs, zip and upload.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
