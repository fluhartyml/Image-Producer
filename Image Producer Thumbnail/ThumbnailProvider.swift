//
//  ThumbnailProvider.swift
//  Image Producer Thumbnail
//
//  REM: 016 B1 PREVIEW ICON, his choice 10-05 ("a saved project shows its own picture in Finder
//  and Files") and 007 (Mac and iPad, Apple's thumbnail extension). A project is a package; on
//  every save the app tucks its own flattened picture inside it at QuickLook/Thumbnail.png
//  (ProjectThumbnail in the app). This extension only hands that picture to the system — it
//  never decodes layers, so it can never draw a project differently from the app itself.
//  A file saved by a build before 016 has no picture yet: it keeps the plain document icon
//  until it is opened and saved once.
//

import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let picture = request.fileURL.appendingPathComponent("QuickLook/Thumbnail.png")
        guard FileManager.default.fileExists(atPath: picture.path) else {
            handler(nil, CocoaError(.fileReadNoSuchFile))
            return
        }
        handler(QLThumbnailReply(imageFileURL: picture), nil)
    }
}
