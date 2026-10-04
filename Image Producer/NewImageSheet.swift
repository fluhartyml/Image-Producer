//
//  NewImageSheet.swift
//  Image Producer
//
//  Asks for a name and a size the moment a new image is made.
//
//  Michael, 2026-10-03, on the iPad: "since i tapped create new image it should ask me the
//  name and dimentions." Before this, a new image opened as "Untitled", 1024 × 1024, and the
//  name and size had to be found in the Canvas tool afterward.
//
//  The sheet only COLLECTS. The size is set here; the name is handed to the Canvas tool
//  (`ImageDocument.pendingNewName`), which already knows how to rename the file on disk —
//  one renaming path, not two. Cancel keeps the defaults.
//

import SwiftUI

struct NewImageSheet: View {
    @ObservedObject var document: ImageDocument
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var width = 1024
    @State private var height = 1024

    /// A few common starting sizes. Every other preset is in the Canvas tool.
    private let sizes: [(label: String, w: Int, h: Int)] = [
        ("Square — 1024 × 1024", 1024, 1024),
        ("Web banner — 1500 × 500", 1500, 500),
        ("HD video — 1920 × 1080", 1920, 1080),
        ("Portrait post — 1080 × 1350", 1080, 1350),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Image").font(.system(size: 24, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 18)).foregroundStyle(.secondary)
                TextField("Untitled", text: $name)
                    .textFieldStyle(.roundedBorder).font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Size in pixels").font(.system(size: 18)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("W", value: $width, format: .number)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 90)
                    Text("×").font(.system(size: 18))
                    TextField("H", value: $height, format: .number)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 90)
                    Menu("Sizes") {
                        ForEach(sizes, id: \.label) { s in
                            Button(s.label) { width = s.w; height = s.h }
                        }
                    }
                    .font(.system(size: 18))
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(width < 1 || height < 1)
            }
            .font(.system(size: 18))
        }
        .padding(24)
        .frame(minWidth: 420)
        .onAppear { width = document.canvasWidth; height = document.canvasHeight }
    }

    private func create() {
        document.canvasWidth = max(1, width)
        document.canvasHeight = max(1, height)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { document.pendingNewName = trimmed }
        dismiss()
    }
}
