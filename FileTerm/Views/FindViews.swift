import FileTermCore
import SwiftUI

/// Toolbar search field, criteria panel and folder-scope indicator.
struct FindToolbar: View {
  let browser: BrowserModel
  @Bindable var settings: AppSettings
  let localProvider: LocalFileSystemProvider
  @Binding var query: SearchQuery
  var focus: FocusState<Bool>.Binding
  @State private var showCriteria = false

  private var pane: PaneModel { browser.activePane }
  private var scopeLocation: Location? { pane.searchScope?.root ?? pane.location }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("Search", text: $query.text)
        .textFieldStyle(.plain).frame(width: 150).focused(focus)
        .onSubmit { run() }
        .accessibilityIdentifier("searchField")
      Button {
        showCriteria.toggle()
      } label: {
        Image(systemName: "slider.horizontal.3")
      }
      .buttonStyle(.borderless).help("Search criteria")
      .accessibilityLabel("Search Criteria").accessibilityIdentifier("searchCriteria")
      .popover(isPresented: $showCriteria) { criteriaPanel }
      if let location = scopeLocation {
        Text("in \(URL(fileURLWithPath: location.path).lastPathComponent.nonEmpty ?? "/")")
          .font(.caption).foregroundStyle(.secondary).lineLimit(1)
          .help(location.path).accessibilityIdentifier("searchScopeIndicator")
          .accessibilityValue(location.path)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
  }

  private var criteriaPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Match").font(.headline)
      Toggle("Name", isOn: $query.matchName)
      Toggle("Extension", isOn: $query.matchExtension)
      Toggle("Tag", isOn: $query.matchTag)
      Toggle("File contents", isOn: $query.matchContents)
      Divider()
      Toggle("Include subfolders", isOn: $settings.searchIncludeSubfolders)
        .accessibilityIdentifier("searchSubfolders")
      Toggle("Include hidden items", isOn: $query.includeHidden)
      Divider()
      Picker("Engine", selection: $settings.searchEngine) {
        ForEach(SearchEngine.allCases, id: \.self) { engine in
          Text(engine.rawValue).tag(engine)
        }
      }.accessibilityIdentifier("searchEngine")
      if let location = scopeLocation,
        let reason = SearchEngine.spotlight.unavailableReason(for: location)
      {
        Text(reason).font(.caption).foregroundStyle(.secondary)
      }
      Text("Searching in " + (scopeLocation?.path ?? "—")).font(.caption)
        .foregroundStyle(.secondary).lineLimit(2)
      Button("Search") {
        showCriteria = false
        run()
      }.keyboardShortcut(.defaultAction)
    }.padding(14).frame(width: 260)
  }

  func run() {
    guard let root = pane.searchScope?.root ?? pane.location else { return }
    var request = query
    request.includeSubfolders = settings.searchIncludeSubfolders
    request.engine = settings.searchEngine.isAvailable(for: root) ? settings.searchEngine : .builtIn
    if !request.matchName && !request.matchExtension && !request.matchTag && !request.matchContents
    {
      request.matchName = true
      query.matchName = true
    }
    let model = pane
    let provider = localProvider
    model.spotlightRunner = { search, root in
      try await SpotlightSearch.run(search, in: root, provider: provider)
    }
    if request.isEmpty {
      model.closeSearch()
      return
    }
    Task { await model.search(request) }
  }
}

extension String {
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}

/// Banner shown above a pane's content while its result scope is open.
struct SearchResultsBanner: View {
  @Bindable var pane: PaneModel

  var body: some View {
    if let scope = pane.searchScope {
      HStack(spacing: 8) {
        if scope.isRunning {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "magnifyingglass")
        }
        Text(summary(scope)).lineLimit(1).accessibilityIdentifier("searchSummary")
        Spacer()
        Button("Close Search") { pane.closeSearch() }
          .accessibilityIdentifier("closeSearch")
      }
      .font(.callout).padding(.horizontal, 8).padding(.vertical, 5)
      .background(Color.accentColor.opacity(0.12))
      Divider()
      if let error = scope.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle").font(.callout)
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        Divider()
      }
    }
  }

  private func summary(_ scope: SearchScope) -> String {
    let count = scope.results.count
    let word = scope.isRunning ? "Searching" : "\(count) result\(count == 1 ? "" : "s")"
    return
      "\(word) for “\(scope.query.text)” in \(scope.root.path) · \(scope.query.engine.rawValue)"
  }
}
