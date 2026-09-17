import SwiftUI
import AppKit

@MainActor final class Session: ObservableObject {
    @Published var folder: URL?
    @Published var files: [URL] = []
    @Published var index = 0
    @Published var photo: Photo?
    @Published var selection = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var busy = false
    @Published var error: String?
    @Published var history: [CropRecord] = []
    @Published var notice = ""
    @Published var thumbnailRevisions: [URL: Int] = [:]
    @Published var processed: [String: String] = [:]
    @Published var pendingOnly = false
    @Published var originalImage: CGImage?
    @Published var showSidebar = true
    @Published var rememberCrop = UserDefaults.standard.bool(forKey: "rememberCrop") {
        didSet { UserDefaults.standard.set(rememberCrop, forKey: "rememberCrop") }
    }
    @Published var cropSpeed = UserDefaults.standard.object(forKey: "cropSpeed") as? Double ?? 0.25 {
        didSet { UserDefaults.standard.set(cropSpeed, forKey: "cropSpeed") }
    }
    @Published var aspect = "Libre" {
        didSet { selection = CropGeometry.fit(selection, ratio: normalizedRatio) }
    }
    private var previousProcessed: [String?] = []
    private var remembered: CGRect? {
        get {
            guard let a = UserDefaults.standard.array(forKey: "rememberedCrop") as? [Double], a.count == 4 else { return nil }
            return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
        }
        set {
            if let r = newValue { UserDefaults.standard.set([r.minX,r.minY,r.width,r.height], forKey: "rememberedCrop") }
        }
    }
    var normalizedRatio: CGFloat? {
        guard let photo else { return nil }
        let ratios: [String: CGFloat] = ["1:1": 1, "4:3": 4/3, "3:2": 1.5, "9:16": 9/16]
        return ratios[aspect].map { $0 * CGFloat(photo.image.height) / CGFloat(photo.image.width) }
    }
    var visiblePositions: [Int] { files.indices.filter { !pendingOnly || processed[files[$0].lastPathComponent] == nil } }
    private var stateKey: String { "processed:" + (folder?.path ?? "") }
    private func persistProcessed() { UserDefaults.standard.set(processed, forKey: stateKey) }
    private var prefetched: Task<Photo?, Never>?
    private var prefetchURL: URL?
    var finished: Bool { !files.isEmpty && index >= files.count }
    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Abrir carpeta"; panel.message = "Elige tus fotos. Cada recorte tendrá un respaldo automático."
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL) {
        do {
            let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            let photos = entries.filter {
                let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true && ["jpg","jpeg","png","heic","heif","tif","tiff"].contains($0.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            folder = url; files = photos; history = []; notice = ""; error = nil
            processed = UserDefaults.standard.dictionary(forKey: stateKey) as? [String: String] ?? [:]
            previousProcessed = []
            thumbnailRevisions = [:]
            prefetched = nil; prefetchURL = nil
            let saved = UserDefaults.standard.string(forKey: "position:" + url.path)
            index = photos.firstIndex(where: { $0.lastPathComponent == saved }) ?? 0
            UserDefaults.standard.set(url.path, forKey: "lastFolder")
            load()
        } catch { self.error = error.localizedDescription }
    }
    func load() {
        photo = nil; originalImage = nil; reset(); error = nil
        guard files.indices.contains(index) else { busy = false; return }
        let url = files[index]
        UserDefaults.standard.set(url.lastPathComponent, forKey: "position:" + (folder?.path ?? ""))
        busy = true
        let cached = prefetchURL == url ? prefetched : nil
        Task {
            do {
                let ready = await cached?.value
                let loaded: Photo
                if let ready, (try? Data(contentsOf: url)) == ready.data { loaded = ready }
                else { loaded = try await Task.detached(priority: .userInitiated) { try PhotoEngine.load(url) }.value }
                photo = loaded
                selection = CropGeometry.fit(rememberCrop ? (remembered ?? CGRect(x: 0, y: 0, width: 1, height: 1)) : CGRect(x: 0, y: 0, width: 1, height: 1), ratio: normalizedRatio)
                if let path = processed[url.lastPathComponent], !path.isEmpty {
                    originalImage = await Task.detached(priority: .utility) { try? PhotoEngine.load(URL(fileURLWithPath: path)).image }.value
                }
            } catch { self.error = error.localizedDescription }
            busy = false
            if files.indices.contains(index+1) {
                let next = files[index+1]; prefetchURL = next
                prefetched = Task.detached(priority: .utility) { try? PhotoEngine.load(next) }
            }
        }
    }
    func reset() { selection = CropGeometry.fit(CGRect(x: 0, y: 0, width: 1, height: 1), ratio: normalizedRatio) }
    func move(_ delta: Int) {
        guard !busy, !files.isEmpty else { return }
        if pendingOnly {
            index = delta > 0 ? (visiblePositions.first(where: { $0 > index }) ?? files.count) : (visiblePositions.last(where: { $0 < index }) ?? index)
        } else { index = min(files.count, max(0,index+delta)) }
        load()
    }
    func select(_ position: Int) {
        guard !busy, files.indices.contains(position), position != index else { return }
        notice = ""
        index = position
        load()
    }
    func save() {
        guard !busy, let photo else { return }
        if selection == CGRect(x:0,y:0,width:1,height:1) {
            processed[photo.url.lastPathComponent] = processed[photo.url.lastPathComponent] ?? ""
            persistProcessed(); remembered = selection; move(1); return
        }
        let crop = selection; busy = true; error = nil
        Task {
            do {
                let record = try await Task.detached(priority: .userInitiated) { try PhotoEngine.crop(photo, selection: crop) }.value
                thumbnailRevisions[record.url, default: 0] += 1
                previousProcessed.append(processed[record.url.lastPathComponent])
                if processed[record.url.lastPathComponent] == nil || processed[record.url.lastPathComponent] == "" {
                    processed[record.url.lastPathComponent] = record.backup.path
                }
                persistProcessed(); remembered = crop
                history.append(record); notice = "Recorte guardado · original respaldada"
                busy = false; move(1)
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
    func undo() {
        guard !busy, let record = history.last else { return }
        busy = true
        Task {
            do {
                try await Task.detached { try PhotoEngine.undo(record) }.value
                thumbnailRevisions[record.url, default: 0] += 1
                let previous = previousProcessed.removeLast()
                processed[record.url.lastPathComponent] = previous
                persistProcessed()
                history.removeLast(); index = files.firstIndex(of: record.url) ?? index
                prefetched = nil; prefetchURL = nil
                notice = "Recorte deshecho"; load()
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

@main struct RecortaApp: App {
    @StateObject private var session = Session()
    var body: some Scene {
        Window("Recorta", id: "main") {
            ContentView(session: session)
                .frame(minWidth: 800, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1220, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir carpeta…", action: session.chooseFolder).keyboardShortcut("o").disabled(session.busy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Deshacer recorte", action: session.undo).keyboardShortcut("z").disabled(session.history.isEmpty || session.busy)
            }
            CommandMenu("Fotos") {
                Button("Mostrar u ocultar miniaturas") { session.showSidebar.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("Recortar y continuar", action: session.save).keyboardShortcut(.return, modifiers: []).disabled(session.busy || session.photo == nil)
                Button("Saltar foto", action: { session.move(1) }).keyboardShortcut(.space, modifiers: []).disabled(session.busy || session.files.isEmpty || session.finished)
                Divider()
                Button("Restablecer selección", action: session.reset).keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}
struct ContentView: View {
    @ObservedObject var session: Session
    @State private var showOptions = false
    private let mint = Color(red: 0.65, green: 0.94, blue: 0.77)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "crop").font(.title2).foregroundStyle(mint)
                Text("Recorta").font(.system(size: 17, weight: .semibold))
                if let folder = session.folder {
                    Text("/").foregroundStyle(.quaternary)
                    Text(folder.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !session.files.isEmpty {
                    Text("\(min(session.index+1,session.files.count)) / \(session.files.count)").monospacedDigit().foregroundStyle(.secondary)
                }
                Button { session.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("Mostrar u ocultar miniaturas · ⌃⌘S")
                Button { showOptions.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Opciones de recorte")
                    .popover(isPresented: $showOptions) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Opciones de recorte").font(.headline)
                            Toggle("Recordar el último encuadre", isOn: $session.rememberCrop)
                            Text("Se aplica a la siguiente foto como punto de partida.").font(.caption).foregroundStyle(.secondary)
                            Picker("Velocidad", selection: $session.cropSpeed) {
                                Text("Precisa").tag(0.10)
                                Text("Normal").tag(0.25)
                                Text("Rápida").tag(0.50)
                            }
                            Text("⇧ acelera · ⌥ amplía · mantén B para ver la original").font(.caption).foregroundStyle(.secondary)
                        }.padding(22).frame(width: 360)
                    }
                Button(action: session.chooseFolder) { Label("Abrir carpeta", systemImage: "folder") }.disabled(session.busy)
            }.padding(.leading, 80).padding(.trailing, 24).frame(height: 66)
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                if !session.files.isEmpty && session.showSidebar {
                    PhotoSidebar(session: session)
                    Divider()
                }
            ZStack {
                Color(red: 0.065, green: 0.073, blue: 0.085)
                if let photo = session.photo {
                    CropCanvas(photo: photo, selection: $session.selection, enabled: !session.busy && !showOptions, speed: session.cropSpeed, ratio: session.normalizedRatio, original: session.originalImage).allowsHitTesting(!session.busy)
                } else if session.busy {
                    ProgressView("Preparando foto…")
                } else if session.finished {
                    emptyState(icon: "checkmark.circle", title: "Fin de la lista", subtitle: "Elige otra foto en la barra lateral o abre una nueva carpeta.")
                } else if session.error == nil {
                    VStack(spacing: 24) {
                        emptyState(icon: "crop", title: session.folder == nil ? "Quédate con lo mejor." : "No hay fotos en esta carpeta", subtitle: "Arrastra. Presiona Enter. Siguiente foto.")
                        Button("Elegir carpeta de fotos", action: session.chooseFolder).buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black).controlSize(.large)
                        if session.folder == nil, let previous = UserDefaults.standard.string(forKey: "lastFolder") {
                            Button("Continuar con \(URL(fileURLWithPath: previous).lastPathComponent)") { session.open(URL(fileURLWithPath: previous)) }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        Text("JPEG · PNG · HEIC · TIFF").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if session.busy && session.photo != nil {
                    ProgressView("Guardando…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            }
            if let error = session.error {
                HStack { Image(systemName: "exclamationmark.circle"); Text(error); Spacer(); Button("Saltar ␣") { session.move(1) }.disabled(session.busy) }
                    .font(.callout).padding(12).background(Color.orange.opacity(0.13))
            }
            Divider().opacity(0.5)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.photo?.url.lastPathComponent ?? "Tu encuadre. Sin distracciones.").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if let photo = session.photo, let rect = try? PhotoEngine.pixelRect(session.selection, width: photo.image.width, height: photo.image.height) {
                        Text("\(Int(rect.width)) × \(Int(rect.height)) px · \(session.aspect)").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Los originales se respaldan automáticamente").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Picker("Proporción", selection: $session.aspect) {
                    ForEach(["Libre", "1:1", "4:3", "3:2", "9:16"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 90).disabled(session.busy)
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }.help("Deshacer · ⌘Z").disabled(session.history.isEmpty || session.busy)
                Button { session.move(-1) } label: { Image(systemName: "chevron.left") }.disabled(session.index == 0 || session.busy)
                Button("Saltar ␣") { session.move(1) }.disabled(session.files.isEmpty || session.finished || session.busy)
                Button("Recortar y seguir  ↵", action: session.save).buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black).disabled(session.photo == nil || session.busy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            HStack {
                Text(session.notice.isEmpty ? "Flechas: recortar · ⌥: ampliar · ⇧: acelerar · B: original · Espacio: saltar · Esc: restablecer" : session.notice)
                Spacer()
                if let folder = session.folder {
                    Button("Ver respaldos") { NSWorkspace.shared.open(folder.appendingPathComponent(".recorta-backups")) }.buttonStyle(.plain)
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 12)
        }.background(Color(red: 0.10, green: 0.11, blue: 0.125))
    }
    func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48, weight: .ultraLight)).foregroundStyle(mint).padding(24).background(mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 28))
            Text(title).font(.system(size: 32, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }.padding(24)
    }
}
