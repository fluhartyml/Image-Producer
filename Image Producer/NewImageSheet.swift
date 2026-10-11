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
    @Bindable var document: ImageDocument
    /// Closed by setting this, not by `dismiss` — on the iPad, Create did nothing
    /// (Michael, 2026-10-03: "create buttons not wired").
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var width = 1024
    @State private var height = 1024
    /// Decided ONCE, when the sheet appears. Read live, a rename underneath the open sheet
    /// added the Name field after the sheet had sized itself — title and buttons clipped
    /// (his screen, 2026-10-11: "the popup is crammed together").
    @State private var isAutoNamed = true

    /// A few common starting sizes. Every other preset is in the Canvas tool.
    private let sizes: [(label: String, w: Int, h: Int)] = [
        ("Square — W 1024 × H 1024", 1024, 1024),
        ("Web banner — W 1500 × H 500", 1500, 500),
        ("HD video — W 1920 × H 1080", 1920, 1080),
        ("Portrait post — W 1080 × H 1350", 1080, 1350),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Image").font(.system(size: 24, weight: .semibold))

            // A file he already named (Welcome's name field) is not asked again — only an
            // automatic ImageProducerNNNN name is. His word, 2026-10-11: the second ask was
            // "being a hover mom".
            if isAutoNamed {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 18)).foregroundStyle(.secondary)
                // The suggestion is the FILE's real name. Found 2026-10-11: a blank project he had
                // named "Font test", reopened, offered "Untitled" — the name stored inside the file
                // never followed the rename on disk. His words: "it wants to rename to 'untitled'
                // instead of … 'Font test'". Empty field + Create keeps this name.
                TextField(document.pendingNewName ?? fileName ?? document.name, text: $name)
                    .textFieldStyle(.roundedBorder).font(.system(size: 18))
            }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Size in pixels").font(.system(size: 18)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    // W and H labels — his ask, 2026-10-11, so width and height can't be confused.
                    Text("W").font(.system(size: 18)).foregroundStyle(.secondary)
                        .help("Width")
                    TextField("W", value: $width, format: .number)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 90)
                    Text("×").font(.system(size: 18))
                    Text("H").font(.system(size: 18)).foregroundStyle(.secondary)
                        .help("Height")
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
                Button("Cancel") { finish() }
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
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            width = document.canvasWidth; height = document.canvasHeight
            isAutoNamed = fileIsAutoNamed
        }
    }

    /// True when the name is still the automatic one (or unknown) — the only case the
    /// sheet asks for a name.
    private var fileIsAutoNamed: Bool {
        guard let stem = fileName else { return true }
        return stem.range(of: #"^ImageProducer\d{4}$"#, options: .regularExpression) != nil
    }

    /// The project file's name on disk, without its extension — what the Canvas tool's
    /// Project name field shows.
    private var fileName: String? {
        let url = document.movedFileURL ?? document.configuration?.fileURL
        let stem = url?.deletingPathExtension().lastPathComponent ?? ""
        return stem.isEmpty ? nil : stem
    }

    private func create() {
        document.canvasWidth = max(1, width)
        document.canvasHeight = max(1, height)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { document.pendingNewName = trimmed }
        document.say("New image: \(trimmed.isEmpty ? (document.pendingNewName ?? fileName ?? document.name) : trimmed), \(document.canvasWidth) × \(document.canvasHeight)", kind: .edit)
        finish()
    }

    /// Close, and remember this document was asked, so it is never asked twice.
    private func finish() {
        ImageDocument.askedForNewImage.insert(ObjectIdentifier(document))
        document.newImageAsked = true
        isPresented = false
    }
}
