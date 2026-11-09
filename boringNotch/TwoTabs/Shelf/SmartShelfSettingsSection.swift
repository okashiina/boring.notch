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
    @Default(.smartShelfShrinkMaxDimension) private var maxDimension
    @Default(.smartShelfShrinkQuality) private var quality

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

            Toggle("Add new screenshots to the shelf", isOn: $screenshotsEnabled)
                .onChange(of: screenshotsEnabled) {
                    // Enabling without a folder: ask for one right away, undo the toggle if cancelled.
                    if screenshotsEnabled, Defaults[.smartShelfScreenshotFolderBookmark] == nil {
                        if ScreenshotWatcher.chooseFolder() {
                            screenshotFolderPath = Defaults[.smartShelfScreenshotFolderPath]
                        } else {
                            screenshotsEnabled = false
                        }
                    }
                }
            HStack {
                Button("Choose screenshot folder…") {
                    if ScreenshotWatcher.chooseFolder() {
                        screenshotFolderPath = Defaults[.smartShelfScreenshotFolderPath]
                    }
                }
                Spacer()
                Text(screenshotFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "No folder chosen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text("Any new png, jpg or heic file that appears in that folder is added. Your Mac's screenshot folder is suggested in the picker.")
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
