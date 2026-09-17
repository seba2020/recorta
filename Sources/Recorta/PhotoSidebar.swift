import SwiftUI
import ImageIO

// Serial decoding and a bounded cache keep large folders from loading all originals.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.totalCostLimit = 32 * 1024 * 1024 }

    func image(for url: URL, revision: Int) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(revision)|\(url.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
}

struct PhotoSidebar: View {
    @ObservedObject var session: Session
    private let mint = Color(red: 0.65, green: 0.94, blue: 0.77)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FOTOS").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                Spacer()
                Text("\(session.files.count)").font(.caption).monospacedDigit()
            }.foregroundStyle(.secondary).padding(16)
            Toggle("Solo pendientes", isOn: $session.pendingOnly)
                .toggleStyle(.checkbox).font(.caption).padding(.horizontal, 16).padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if session.visiblePositions.isEmpty {
                            Text("No quedan fotos pendientes").font(.caption).foregroundStyle(.secondary).padding()
                        }
                        ForEach(session.visiblePositions, id: \.self) { position in
                            let url = session.files[position]
                            Button { session.select(position) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    PhotoThumbnail(url: url, revision: session.thumbnailRevisions[url, default: 0])
                                        .id("\(url.path)|\(session.thumbnailRevisions[url, default: 0])")
                                    HStack(spacing: 5) {
                                        Text("\(position + 1)").monospacedDigit().foregroundStyle(.secondary)
                                        if session.processed[url.lastPathComponent] != nil {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(mint).help("Procesada")
                                        }
                                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    }.font(.system(size: 10, weight: session.index == position ? .semibold : .regular))
                                }
                                .padding(8)
                                .background(session.index == position ? mint.opacity(0.12) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(session.index == position ? mint : .clear, lineWidth: 1.5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(session.busy)
                            .help(url.lastPathComponent)
                            .accessibilityLabel("Foto \(position + 1): \(url.lastPathComponent)")
                            .accessibilityAddTraits(session.index == position ? .isSelected : [])
                            .id(url)
                        }
                    }.padding(.horizontal, 10).padding(.bottom, 12)
                }
                .onChange(of: session.index) { _, _ in
                    if session.files.indices.contains(session.index) {
                        withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(session.files[session.index]) }
                    }
                }
                .onAppear {
                    if session.files.indices.contains(session.index) { proxy.scrollTo(session.files[session.index]) }
                }
            }
        }
        .frame(width: 184)
        .background(Color(red: 0.085, green: 0.094, blue: 0.108))
    }
}

private struct PhotoThumbnail: View {
    let url: URL
    let revision: Int
    @State private var image: NSImage?
    @State private var loaded = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.25))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: loaded ? "photo.badge.exclamationmark" : "photo")
                    .font(.title2).foregroundStyle(.tertiary)
            }
        }
        .frame(height: 98)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: "\(url.path)|\(revision)") {
            let result = await ThumbnailLoader.shared.image(for: url, revision: revision)
            guard !Task.isCancelled else { return }
            image = result; loaded = true
        }
    }
}
